/**
 * Server-only exports from @online-code-sandbox/shared.
 * These modules depend on Node.js APIs and must NOT be bundled into the browser.
 *
 * Import from '@online-code-sandbox/shared/server' in api/worker code.
 */

// Logging
export { createLogger } from './logger.js';
export type { Logger } from './logger.js';

// Tracing
export {
  initTracing,
  startRootSpan,
  startLinkedSpan,
  shutdownTracing,
  SpanStatusCode,
} from './tracing.js';
export type { Span } from './tracing.js';
