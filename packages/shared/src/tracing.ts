import { trace, context, TraceFlags } from '@opentelemetry/api';
import type { Span } from '@opentelemetry/api';
import { NodeTracerProvider, BatchSpanProcessor } from '@opentelemetry/sdk-trace-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { resourceFromAttributes } from '@opentelemetry/resources';

let registered = false;

/** Registers a NodeTracerProvider exporting to Tempo via OTLP/HTTP. Call once per process. */
export function initTracing(service: string): void {
  if (registered) return;
  registered = true;

  const provider = new NodeTracerProvider({
    resource: resourceFromAttributes({ 'service.name': service }),
    spanProcessors: [
      new BatchSpanProcessor(
        new OTLPTraceExporter({
          url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://tempo:4318/v1/traces',
        }),
      ),
    ],
  });
  provider.register();
}

/** Starts a new root span, returning the IDs needed to link a child span across a process boundary (e.g. a Redis queue). */
export function startRootSpan(
  service: string,
  name: string,
  attributes?: Record<string, string>,
): { span: Span; traceId: string; spanId: string } {
  const span = trace.getTracer(service).startSpan(name, { attributes });
  const { traceId, spanId } = span.spanContext();
  return { span, traceId, spanId };
}

/** Starts a child span linked to a parent whose IDs crossed a process boundary. */
export function startLinkedSpan(
  service: string,
  name: string,
  parentTraceId: string,
  parentSpanId: string,
  attributes?: Record<string, string>,
): Span {
  const parentContext = trace.setSpanContext(context.active(), {
    traceId: parentTraceId,
    spanId: parentSpanId,
    traceFlags: TraceFlags.SAMPLED,
    isRemote: true,
  });
  return trace.getTracer(service).startSpan(name, { attributes }, parentContext);
}

export type { Span };
