import crypto from 'node:crypto';
import {
  ExecutionStatus,
  executionKey,
  EXECUTION_TTL_SECONDS,
  validateExecutionRequest,
  isTerminalStatus,
  startRootSpan,
} from '@online-code-sandbox/shared';
import type {
  ExecutionState,
  ExecutionRequest,
  CreateExecutionResponse,
} from '@online-code-sandbox/shared';
import { redis } from './redisClient.js';
import { enqueueExecution } from './queue.js';
import { executionsSubmittedTotal } from '../server.js';

/**
 * Transport-agnostic execution service.
 *
 * This module contains all business logic for managing executions.
 * It knows nothing about Express req/res — route handlers and future
 * WebSocket handlers both delegate to these functions.
 */

// ── Errors ──────────────────────────────────────────────────────────────────

export class ValidationError extends Error {
  public readonly errors: string[];
  constructor(errors: string[]) {
    super(errors.join('; '));
    this.name = 'ValidationError';
    this.errors = errors;
  }
}

// ── Cancel result type ──────────────────────────────────────────────────────

export type CancelResult =
  | { success: true }
  | { success: false; reason: 'NOT_FOUND' | 'ALREADY_TERMINAL'; currentStatus?: string };

// ── Service functions ───────────────────────────────────────────────────────

/**
 * Create a new execution: validate → generate ID → store QUEUED state → enqueue.
 * Returns immediately — does NOT wait for execution to complete.
 */
export async function createExecution(body: unknown): Promise<CreateExecutionResponse> {
  const validation = validateExecutionRequest(body);
  if (!validation.valid) {
    throw new ValidationError(validation.errors);
  }

  const { language, source } = body as ExecutionRequest;
  const executionId = crypto.randomUUID();

  const { span, traceId, spanId } = startRootSpan('api', 'submit_execution', {
    executionId,
    language,
  });

  const state: ExecutionState = {
    executionId,
    status: ExecutionStatus.QUEUED,
    language,
    source,
    createdAt: new Date().toISOString(),
    startedAt: null,
    completedAt: null,
    output: null,
    exitCode: null,
    error: null,
  };

  const key = executionKey(executionId);
  await redis.set(key, JSON.stringify(state), 'EX', EXECUTION_TTL_SECONDS);
  await enqueueExecution({ executionId, language, source, traceId, spanId });
  executionsSubmittedTotal.inc();

  span.end();

  return { executionId };
}

/**
 * Get execution state from Redis.
 * Returns null if the execution doesn't exist or has expired.
 */
export async function getExecution(executionId: string): Promise<ExecutionState | null> {
  const data = await redis.get(executionKey(executionId));
  if (!data) return null;
  return JSON.parse(data) as ExecutionState;
}

/**
 * Cancel an execution. Marks it as CANCELLED if it hasn't reached a terminal state.
 * Note: This does not kill a running Docker container — that's a known limitation.
 */
export async function cancelExecution(executionId: string): Promise<CancelResult> {
  const key = executionKey(executionId);
  const data = await redis.get(key);

  if (!data) {
    return { success: false, reason: 'NOT_FOUND' };
  }

  const state = JSON.parse(data) as ExecutionState;

  if (isTerminalStatus(state.status)) {
    return { success: false, reason: 'ALREADY_TERMINAL', currentStatus: state.status };
  }

  state.status = ExecutionStatus.CANCELLED;
  state.completedAt = new Date().toISOString();

  // Preserve remaining TTL
  const ttl = await redis.ttl(key);
  await redis.set(key, JSON.stringify(state), 'EX', ttl > 0 ? ttl : EXECUTION_TTL_SECONDS);

  return { success: true };
}
