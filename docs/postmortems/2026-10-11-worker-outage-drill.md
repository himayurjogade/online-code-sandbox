# Postmortem: Worker Outage (Incident Drill)

**Date:** 2026-10-11
**Type:** Deliberate drill (chaos test), not a real production incident
**Status:** Resolved
**Severity:** Would have been Critical in production (full processing outage)

## Summary

The worker service was deliberately stopped (`scripts/chaos-kill-worker.sh`) while
`scripts/load-test.sh` fired 40 concurrent executions at the API, to verify that:

1. A real outage is actually detected by an alert, not just visible after the fact in a dashboard
2. The alert fires within a reasonable time of the outage starting
3. The system recovers cleanly once the worker comes back

This is a blameless writeup — the goal was to test the monitoring/alerting setup
itself, not to find fault. One real gap was found (see **Action Items**).

## Impact (as simulated)

- All 40 submissions during the outage window sat in the Redis queue
  (`execution:queue`) with status `QUEUED`, making zero progress.
- Had this been real traffic, every user during this window would have seen
  their code "stuck" indefinitely until the worker recovered.
- No executions were lost — Redis retained the queue exactly as expected, and
  all 40 drained and completed normally once the worker restarted.

## Timeline (UTC, from actual drill logs)

| Time     | Event                                                                                                 |
| -------- | ----------------------------------------------------------------------------------------------------- |
| 14:03:01 | Drill started. Baseline checked: zero active alerts, system healthy.                                  |
| 14:03:01 | `docker compose stop worker` — worker taken offline.                                                  |
| 14:03:0x | 40 executions submitted via load-test script; confirmed stuck in Redis (`LLEN execution:queue` = 40). |
| 14:04:04 | **`WorkerDown` alert starts firing** in Prometheus and Alertmanager — ~63s after the outage began.    |
| 14:06:41 | `docker compose start worker` — worker restored.                                                      |
| 14:07:01 | Queue fully drained (`execution:queue` = 0), worker's `up` metric back to `1`.                        |
| 14:07:01 | `WorkerDown` alert returns to `inactive` in Prometheus; Alertmanager shows zero active alerts.        |

**Total simulated outage:** ~3m40s. **Detection lag:** ~63s (expected — the alert
rule has `for: 1m`, i.e. it waits 1 minute of sustained failure before firing, to
avoid paging on a single missed scrape).

## Root Cause

Simulated — the worker container was stopped intentionally via Docker Compose.
In a real incident this same signal (`up{job="worker"} == 0`) would equally catch
a crash, an OOM kill, a bad deploy, or the container losing network connectivity —
anything that stops Prometheus from being able to scrape it.

## Detection

`WorkerDown` (based on Prometheus's own `up` metric, which doesn't depend on the
worker successfully reporting anything about itself) worked exactly as designed —
it fired without needing the worker to cooperate in any way.

## Action Items

1. **Gap found — `QueueBacklogGrowing` did not fire during this drill, even
   though the real backlog reached 40.** That alert's expression (`queue_depth
   > 5`) reads a Gauge that the *worker itself* exports on its own `/metrics`endpoint. When the worker is fully down, Prometheus can't scrape that target
at all, so the`queue_depth` series simply stops updating — the exact
   > scenario where the backlog is growing fastest is the one scenario this
   > alert can't see, because its data source goes dark with the very thing
   > it's supposed to be watching.
   - **Fix direction:** move backlog depth to a source independent of the
     worker process — e.g. have the API (or a separate lightweight exporter)
     report `LLEN` on the queue directly from Redis, since the API's own
     uptime isn't coupled to the worker's.
   - Not fixed in this round — `WorkerDown` already covers the "worker is
     completely gone" case that triggered this drill; this gap matters more
     for a _partial_ slowdown where the worker is up but falling behind,
     which `WorkerDown` would miss entirely.
2. **Confirmed working, no action needed:** `WorkerDown` detection time (~63s)
   is reasonable for this project's scale. No change recommended.
3. **Confirmed working, no action needed:** recovery was clean and automatic —
   no manual intervention was needed to drain the backlog once the worker
   came back; the existing BLPOP loop picked up exactly where it left off.
