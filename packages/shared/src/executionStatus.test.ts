import { describe, it, expect } from 'vitest';
import { ExecutionStatus, isTerminalStatus } from './executionStatus.js';

describe('isTerminalStatus', () => {
  it('treats COMPLETED, TIMEOUT, RUNTIME_ERROR, OUTPUT_LIMIT, CANCELLED as terminal', () => {
    expect(isTerminalStatus(ExecutionStatus.COMPLETED)).toBe(true);
    expect(isTerminalStatus(ExecutionStatus.TIMEOUT)).toBe(true);
    expect(isTerminalStatus(ExecutionStatus.RUNTIME_ERROR)).toBe(true);
    expect(isTerminalStatus(ExecutionStatus.OUTPUT_LIMIT)).toBe(true);
    expect(isTerminalStatus(ExecutionStatus.CANCELLED)).toBe(true);
  });

  it('treats QUEUED and RUNNING as non-terminal', () => {
    expect(isTerminalStatus(ExecutionStatus.QUEUED)).toBe(false);
    expect(isTerminalStatus(ExecutionStatus.RUNNING)).toBe(false);
  });
});
