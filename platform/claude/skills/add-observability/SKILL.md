---
name: add-observability
description: Wires up structured logging, metrics, and error tracking to a service in a way that's pluggable to multiple backends. Use when preparing a service for production or adding monitoring to an existing service.
---

# Add observability

## Self-update on invocation

1. WebSearch for "OpenTelemetry best practices 2026" and current SDK status for the language in use.
2. WebSearch for current recommended self-hosted and SaaS backends.
3. Propose updates. Apply with my approval.

## Steps

1. **Logging**:
   - Structured JSON to stdout.
   - Include: timestamp, level, service name, request_id, customer_id (when applicable), event-specific fields.
   - One log per significant event. Don't double-log.
   - Levels: DEBUG (verbose, off in prod), INFO (normal flow), WARN (degraded but recoverable), ERROR (failure with stack), CRITICAL (data integrity at risk).
2. **Metrics**:
   - OpenTelemetry SDK, OTLP exporter.
   - Standard metrics per service: request rate, error rate, latency (p50, p95, p99), in-flight requests.
   - Custom metrics per business event (e.g., conversations_started, tokens_consumed).
3. **Traces**:
   - OpenTelemetry SDK with automatic instrumentation for the framework + DB + HTTP client.
   - Manual spans around business-significant operations.
4. **Error tracking**:
   - Sentry or current best-practice equivalent (verify via WebSearch).
   - Capture unhandled exceptions, business-significant errors.
   - Scrub PII before sending.
5. **Backend selection** (configure at deploy time, not in code):
   - Logs: Loki (self-hosted), Better Stack, Axiom, Datadog — choose at deploy.
   - Metrics: Prometheus + Grafana (self-hosted), Grafana Cloud free tier, Datadog.
   - Traces: same backends usually accept OTLP.
6. Configuration via env vars. Code emits to OTLP; env decides where OTLP points.
7. Verify locally with a console exporter before deploying.

## Checkpoints

- ASK before adding any paid observability vendor.
- ASK before logging anything that could contain PII or secrets.

## Related skills

- `harden-for-production`
- `monitor-vps`

<!-- last_reviewed: 2026-05-12 -->
