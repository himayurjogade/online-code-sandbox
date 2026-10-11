import type { ExecutionStatus } from '../executionStatus.js';

/**
 * Core execution types shared across API, Worker, and Frontend.
 */

/** Request payload for creating a new execution. */
export interface ExecutionRequest {
  language: string;
  source: string;
}

/** Full execution state stored in Redis. */
export interface ExecutionState {
  executionId: string;
  status: ExecutionStatus;
  language: string;
  source: string;
  createdAt: string;
  startedAt: string | null;
  completedAt: string | null;
  output: string | null;
  exitCode: number | null;
  error: string | null;
}

/** Job payload pushed onto the Redis queue. */
export interface ExecutionJob {
  executionId: string;
  language: string;
  source: string;
  /** IDs of the API's root span, so the worker can link its span as a child across the queue boundary. */
  traceId: string;
  spanId: string;
}

/** Response from POST /api/executions. */
export interface CreateExecutionResponse {
  executionId: string;
}
