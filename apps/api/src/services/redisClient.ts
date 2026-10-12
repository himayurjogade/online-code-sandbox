import { Redis } from 'ioredis';
import { createLogger } from '@online-code-sandbox/shared/server';
import { config } from '../config.js';

const logger = createLogger('api');

/**
 * Singleton Redis client for the API server.
 * All Redis operations in the API go through this client.
 */
export const redis = new Redis(config.redisUrl, {
  maxRetriesPerRequest: 3,
  retryStrategy(times: number) {
    const delay = Math.min(times * 200, 5000);
    return delay;
  },
});

redis.on('error', (err: Error) => {
  logger.error({ err }, 'Redis connection error');
});

redis.on('connect', () => {
  logger.info({ redisUrl: config.redisUrl }, 'Connected to Redis');
});

/** Gracefully close the Redis connection. */
export async function shutdownRedis(): Promise<void> {
  await redis.quit();
  logger.info('Redis connection closed');
}
