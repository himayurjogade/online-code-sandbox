import { describe, it, expect } from 'vitest';
import { validateExecutionRequest } from './validation.js';

describe('validateExecutionRequest', () => {
  it('accepts a valid request', () => {
    const result = validateExecutionRequest({ language: 'python', source: 'print(1)' });
    expect(result.valid).toBe(true);
    expect(result.errors).toEqual([]);
  });

  it('rejects a non-object body', () => {
    expect(validateExecutionRequest(null).valid).toBe(false);
    expect(validateExecutionRequest('nope').valid).toBe(false);
    expect(validateExecutionRequest(undefined).valid).toBe(false);
  });

  it('rejects a missing language', () => {
    const result = validateExecutionRequest({ source: 'print(1)' });
    expect(result.valid).toBe(false);
    expect(result.errors.some((e) => e.includes('language'))).toBe(true);
  });

  it('rejects an unsupported language', () => {
    const result = validateExecutionRequest({ language: 'cobol', source: 'print(1)' });
    expect(result.valid).toBe(false);
    expect(result.errors.some((e) => e.includes('Unsupported language'))).toBe(true);
  });

  it('rejects a missing source', () => {
    const result = validateExecutionRequest({ language: 'python' });
    expect(result.valid).toBe(false);
    expect(result.errors.some((e) => e.includes('source'))).toBe(true);
  });

  it('rejects an empty source', () => {
    const result = validateExecutionRequest({ language: 'python', source: '   ' });
    expect(result.valid).toBe(false);
  });

  it('rejects source exceeding the max size', () => {
    const huge = 'a'.repeat(65537);
    const result = validateExecutionRequest({ language: 'python', source: huge });
    expect(result.valid).toBe(false);
    expect(result.errors.some((e) => e.includes('exceeds maximum size'))).toBe(true);
  });

  it('accepts every supported language', () => {
    for (const language of ['python', 'javascript', 'cpp', 'c', 'java']) {
      const result = validateExecutionRequest({ language, source: 'noop' });
      expect(result.valid).toBe(true);
    }
  });
});
