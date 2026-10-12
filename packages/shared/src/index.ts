/**
 * Barrel export for @online-code-sandbox/shared.
 * Single import point for all shared types and utilities.
 */

// Status enum and helpers
export { ExecutionStatus, TERMINAL_STATUSES, isTerminalStatus } from './executionStatus.js';

// Redis key patterns
export { executionKey, QUEUE_NAME, EXECUTION_TTL_SECONDS } from './redisKeys.js';

// Validation
export { validateExecutionRequest } from './validation.js';
export type { ValidationResult } from './validation.js';

// Core types
export type {
  ExecutionRequest,
  ExecutionState,
  ExecutionJob,
  CreateExecutionResponse,
} from './types/execution.js';

// Event contracts (for future streaming)
export type {
  ExecutionOutputChunk,
  ExecutionStatusChange,
  ExecutionInputMessage,
  ServerEvent,
  ClientEvent,
} from './types/events.js';
