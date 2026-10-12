import express from 'express';
import cors from 'cors';
import { config } from './config.js';
import { executionsRouter } from './routes/executions.js';
import { errorHandler } from './middleware/errorHandler.js';
import { shutdownRedis } from './services/redisClient.js';
import { createLogger, initTracing, shutdownTracing } from '@online-code-sandbox/shared/server';
import client from 'prom-client';
import os from 'node:os';

initTracing('api');
const logger = createLogger('api');

// ── Metrics Setup ────────────────────────────────────────────────────────────

client.register.setDefaultLabels({
  replica_id: os.hostname(),
  service: 'api',
});
client.collectDefaultMetrics();

export const executionsSubmittedTotal = new client.Counter({
  name: 'executions_submitted_total',
  help: 'Total number of execution jobs submitted to the queue',
});

const httpRequestsTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests processed',
  labelNames: ['method', 'route', 'status_code'],
});

const app = express();

// ── Middleware ───────────────────────────────────────────────────────────────

app.use(cors());
app.use(express.json({ limit: '1mb' }));

app.use((req, res, next) => {
  res.on('finish', () => {
    // Avoid tracking the metrics endpoint itself
    if (req.path !== '/metrics') {
      httpRequestsTotal
        .labels(req.method, req.route?.path || req.path, res.statusCode.toString())
        .inc();
    }
  });
  next();
});

// ── Routes ──────────────────────────────────────────────────────────────────

app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.get('/metrics', async (_req, res) => {
  try {
    res.set('Content-Type', client.register.contentType);
    res.end(await client.register.metrics());
  } catch (ex) {
    res.status(500).end(ex);
  }
});

app.use('/api/executions', executionsRouter);

// ── Error handler (must be registered last) ─────────────────────────────────

app.use(errorHandler);

// ── Start server ────────────────────────────────────────────────────────────

const server = app.listen(config.port, () => {
  logger.info({ port: config.port }, 'Server listening');
});

// ── Graceful shutdown ───────────────────────────────────────────────────────

async function shutdown(signal: string) {
  logger.info({ signal }, 'Shutdown signal received');
  server.close();
  await shutdownRedis();
  await shutdownTracing();
  process.exit(0);
}

process.on('SIGTERM', () => void shutdown('SIGTERM'));
process.on('SIGINT', () => void shutdown('SIGINT'));
