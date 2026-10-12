import { Redis } from 'ioredis';
import {
  ExecutionStatus,
  executionKey,
  EXECUTION_TTL_SECONDS,
  isTerminalStatus,
} from '@online-code-sandbox/shared';
import type { ExecutionState, ExecutionJob } from '@online-code-sandbox/shared';
import {
  createLogger,
  initTracing,
  startLinkedSpan,
  shutdownTracing,
  SpanStatusCode,
} from '@online-code-sandbox/shared/server';
import { config } from './config.js';
import { waitForJob, shutdownQueue } from './queue.js';
import { DockerEngine } from './engines/dockerEngine.js';
import type { ExecutionEngine } from './engines/types.js';
import { QUEUE_NAME } from '@online-code-sandbox/shared';
import express from 'express';
import client from 'prom-client';
import os from 'node:os';

initTracing('worker');
const logger = createLogger('worker');

// ── Metrics Setup ────────────────────────────────────────────────────────────

client.register.setDefaultLabels({
  replica_id: os.hostname(),
  service: 'worker',
});
client.collectDefaultMetrics();

const executionsProcessedTotal = new client.Counter({
  name: 'executions_processed_total',
  help: 'Total number of execution jobs processed',
  labelNames: ['status'],
});

const executionDurationSeconds = new client.Histogram({
  name: 'execution_duration_seconds',
  help: 'Duration of execution in seconds (including docker spinup)',
  buckets: [0.1, 0.5, 1, 2, 5, 10], // Bucket limits in seconds
});

// We can asynchronously collect the queue length when Prometheus scrapes
new client.Gauge({
  name: 'queue_depth',
  help: 'Number of jobs in the execution queue',
  async collect() {
    try {
      this.set(await redis.llen(QUEUE_NAME));
    } catch {
      this.set(0);
    }
  },
});

const metricsApp = express();
metricsApp.get('/metrics', async (_req, res) => {
  try {
    res.set('Content-Type', client.register.contentType);
    res.end(await client.register.metrics());
  } catch (ex) {
    res.status(500).end(ex);
  }
});
const metricsServer = metricsApp.listen(3001, '0.0.0.0', () => {
  logger.info({ port: 3001 }, 'Metrics server listening');
});

/**
 * Worker main loop.
 *
 * 1. Blocks on Redis queue for the next job
 * 2. Checks if cancelled before starting
 * 3. Updates status to RUNNING
 * 4. Executes code via the ExecutionEngine
 * 5. Writes final result back to Redis
 */

// ── Redis client for state updates (non-blocking) ───────────────────────────

const redis = new Redis(config.redisUrl);

redis.on('error', (err: Error) => {
  logger.error({ err }, 'Redis error');
});

// ── Engine ──────────────────────────────────────────────────────────────────

const engine: ExecutionEngine = new DockerEngine();

// ── State helpers ───────────────────────────────────────────────────────────

async function getState(executionId: string): Promise<ExecutionState | null> {
  const data = await redis.get(executionKey(executionId));
  return data ? (JSON.parse(data) as ExecutionState) : null;
}

async function updateState(state: ExecutionState): Promise<void> {
  const key = executionKey(state.executionId);
  const ttl = await redis.ttl(key);
  await redis.set(key, JSON.stringify(state), 'EX', ttl > 0 ? ttl : EXECUTION_TTL_SECONDS);
}

// ── Job processor ───────────────────────────────────────────────────────────

async function processJob(job: ExecutionJob): Promise<void> {
  const { executionId, language, source, traceId, spanId } = job;
  const log = logger.child({ executionId });
  log.info({ language }, 'Processing job');

  const endTimer = executionDurationSeconds.startTimer();

  // Check if already cancelled before starting
  const state = await getState(executionId);
  if (!state) {
    log.warn('State not found (expired?), skipping');
    endTimer();
    return;
  }
  if (isTerminalStatus(state.status)) {
    log.info({ status: state.status }, 'Already terminal, skipping');
    endTimer();
    return;
  }

  // Mark as RUNNING
  state.status = ExecutionStatus.RUNNING;
  state.startedAt = new Date().toISOString();
  await updateState(state);

  // Execute
  const span = startLinkedSpan('worker', 'execute_in_sandbox', traceId, spanId, {
    executionId,
    language,
  });
  try {
    const result = await engine.execute({
      executionId,
      language,
      source,
      timeoutMs: config.executionTimeoutMs,
      maxOutputBytes: config.maxOutputBytes,
    });

    // Determine final status
    if (result.timedOut) {
      state.status = ExecutionStatus.TIMEOUT;
    } else if (result.outputTruncated) {
      state.status = ExecutionStatus.OUTPUT_LIMIT;
    } else if (result.exitCode !== 0) {
      state.status = ExecutionStatus.RUNTIME_ERROR;
    } else {
      state.status = ExecutionStatus.COMPLETED;
    }

    state.output = result.stdout;
    state.exitCode = result.exitCode;
    state.error = result.stderr || null;
  } catch (err) {
    state.status = ExecutionStatus.RUNTIME_ERROR;
    state.error = err instanceof Error ? err.message : 'Unknown execution error';
    state.exitCode = -1;
    span.setStatus({ code: SpanStatusCode.ERROR, message: String(err) });
    if (err instanceof Error) span.recordException(err);
  } finally {
    span.setAttribute('execution.status', state.status);
    span.end();
  }

  state.completedAt = new Date().toISOString();
  await updateState(state);

  executionsProcessedTotal.labels(state.status).inc();
  endTimer();

  log.info({ status: state.status }, 'Job finished');
}

// ── Main loop ───────────────────────────────────────────────────────────────

let running = true;

async function main(): Promise<void> {
  logger.info('Starting — waiting for jobs');

  while (running) {
    try {
      const job = await waitForJob();
      if (!job) continue;
      await processJob(job);
    } catch (err) {
      if (!running) break; // Shutdown in progress
      logger.error({ err }, 'Error processing job');
      // Brief pause before retrying to avoid tight error loops
      await new Promise((resolve) => setTimeout(resolve, 1000));
    }
  }
}

// ── Graceful shutdown ───────────────────────────────────────────────────────

async function shutdown(signal: string): Promise<void> {
  logger.info({ signal }, 'Shutdown signal received');
  running = false;
  metricsServer.close();
  await shutdownQueue();
  await redis.quit();
  await shutdownTracing();
  process.exit(0);
}

process.on('SIGTERM', () => void shutdown('SIGTERM'));
process.on('SIGINT', () => void shutdown('SIGINT'));

// Start
main().catch((err) => {
  logger.error({ err }, 'Fatal error');
  process.exit(1);
});
