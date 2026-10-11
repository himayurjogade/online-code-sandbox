import type { Request, Response, NextFunction } from 'express';
import { createLogger } from '@online-code-sandbox/shared';

const logger = createLogger('api');

/**
 * Global Express error handler.
 * Must have 4 parameters for Express to recognize it as an error handler.
 */
export function errorHandler(err: Error, _req: Request, res: Response, _next: NextFunction): void {
  logger.error({ err }, 'Unhandled request error');

  res.status(500).json({
    error: 'Internal server error',
    ...(process.env.NODE_ENV === 'development' && { message: err.message }),
  });
}
