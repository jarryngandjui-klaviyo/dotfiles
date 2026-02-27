
---
name: kdev-event-gateway
description: Agent context for developing on the Event Gateway (fka Event Pipeline 2025). Grounds answers in local repo facts — source paths, appfiles, Terraform, Kafka topics, and test commands.
---

You are helping me work on Klaviyo's **Event Gateway** codebase.
Always prefer reading local files over giving generic advice.

Before helping write or review a PR description, **always check** the local `.github/pull_request_template.md` (if present in the repo) and follow its structure.

---

## System Overview

The **Event Gateway** is a priority-aware, Kafka-backed ETL buffer that sits in front of the Event Pipeline. It accepts events from various sources, classifies them by SLO priority, and fans them out to downstream processors — handling ~100 billion events per month.

**Predecessor:** RabbitMQ (bottlenecked under BFCM load; migrated to AWS MSK by 2024).

### Priority Levels (assigned by the Event Ingest classifier)

| Level | SLO Target | Description         |
|-------|-----------|---------------------|
| P30   | < 5 sec   | Highest priority (e.g. Flow Triggers) |
| P20   | < 1 min   | Medium priority     |
| P10   | < 20 min  | Low priority        |

### Data Flow

```
Event source
  → IngestService (app)           — Static + Dynamic classify, schedule
  → PrepPublisher (k-repo/KDP)    — gRPC proxy; routes to correct MSK topic
  → AWS MSK (4 clusters)          — Kafka broker; p10/p20/p30/offload/retry/dlq topics
  → Events Orchestrator (k-repo)  — Kafka consumer; in-memory buffer; serves batches
  → Event Pipeline Processor (app QW) — Pulls batches from Orchestrator gRPC; executes
```

---

## Repos

All repos are at `~/Klaviyo/Repos/<repo-name>`.

| Short name | Repo path |
|------------|-----------|
| app        | `~/Klaviyo/Repos/app` |
| k-repo     | `~/Klaviyo/Repos/k-repo` |
| infra      | `~/Klaviyo/Repos/infrastructure-deployment` |
| handbook   | `~/Klaviyo/Repos/eng-handbook` |

---

## Components

### 1. IngestService (app repo)

**Role:** Accepts events, runs static + dynamic classification, calls PrepPublisher.

| Asset | Path |
|-------|------|
| Service source | `~/Klaviyo/Repos/app/src/learning/app/services/events/ingest/service/` |
| Base class | `base.py` in directory above |
| Classifiers | `classifier/static.py`, `classifier/dynamic.py` |
| Scheduler | `scheduler.py` |
| SLO Service | `slo_service.py` (AIMD congestion control) |
| Publisher | `~/Klaviyo/Repos/app/src/learning/app/data_exchange/event_ingest_publisher.py` |
| Tests | `~/Klaviyo/Repos/app/tests/services/events/ingest/service/` |

**SLO Service** uses AIMD (Additive Increase, Multiplicative Decrease) congestion control. Alert threshold: >10 capacity decrements/min for P10 events indicates serious congestion.

**Test commands (app):**
```bash
# Setup first
klaviyocli docker setup

# Full test file
make TEST="tests/services/events/ingest/service/test_base.py" docker-unit

# Single test
make TEST="tests/services/events/ingest/service/test_base.py::ClassName::test_name" docker-unit
```

**Test on-demand snippet:**
```python
from app.data_exchange.event_ingest_publisher import EventIngestPublisher, EventIngest
publisher = EventIngestPublisher()
cid = "V3qGae"
event_ingest = EventIngest(company_id=cid, statistic_key="api")
publisher._publish_payloads_with_client(
    client=publisher._client,
    client_name=publisher.ClientName.PRODUCTION,
    company_id=cid,
    event_payloads=[event_ingest],
    use_fallbacks=False,
)
```

---

### 2. PrepPublisher (k-repo / KDP)

**Role:** gRPC proxy. Receives classified events from IngestService and publishes to the correct MSK priority topic. Each pod holds producers for p10, p20, p30, and offload.

| Asset | Path |
|-------|------|
| Server source | `~/Klaviyo/Repos/k-repo/python/klaviyo/data_exchange/prep_publisher/server/` |
| Key files | `main.py`, `router.py`, `publisher.py`, `settings.py`, `gating.py` |
| Client | `~/Klaviyo/Repos/k-repo/python/klaviyo/data_exchange/prep_publisher/client/` |
| Appfile (prod) | `~/Klaviyo/Repos/infrastructure-deployment/apps/internal-exchange/prep-publisher/app.yaml` |
| Appfile (staging) | `~/Klaviyo/Repos/infrastructure-deployment/apps/internal-exchange/prep-publisher-staging/app.yaml` |
| Terraform | `~/Klaviyo/Repos/infrastructure-deployment/infrastructure/live/prod/internal-exchange/prep-publisher/main.tf` |
| Server tests | `~/Klaviyo/Repos/k-repo/python/klaviyo/data_exchange/prep_publisher/tests/server/` |
| Client tests | `~/Klaviyo/Repos/k-repo/python/klaviyo/data_exchange/prep_publisher/tests/client/` |

**Scale (prod):** HPA 40–150 pods; BFCM pre-scaled to 773 pods.
**Node pool:** `event-pipeline-publisher`
**Prod host:** `prep-publisher-prod.internal.clovesoftware.com`
**Ports:** gRPC `50051`, liveness `50099`, statsd `9102`
**Service tier:** 1 (BFCM critical)
**Statsd key:** `klaviyo.data_exchange.prep_publisher` (staging: `klaviyo.data_exchange.staging_prep_publisher`)

**Rollout:** Per-company CRC32 hash routing to a rollout cluster; controlled by Statsig dynamic config `event_gateway_cluster_rollout_prod`. Rollout producers are initialized only if `rollout_producers_enabled=True`.

**Test commands (k-repo):**
```bash
# Full test file
LOG_LEVEL=info pants test python/klaviyo/data_exchange/prep_publisher/tests/server/test_main.py

# Single test
pants test python/klaviyo/data_exchange/prep_publisher/tests/server/test_main.py -- -k test_name

# Router tests
pants test python/klaviyo/data_exchange/prep_publisher/tests/server/test_router.py

# Client fallback test
pants test python/klaviyo/data_exchange/prep_publisher/tests/client/test_main.py -- -k test_failed_events_fallback_service_failed
```

**Debug: SSH into a staging pod:**
```bash
# List pods
kubectl get pods -n internal-exchange --context prod-edam-d -l app=prep-publisher-staging-prod

# Exec in
kubectl -n internal-exchange --context prod-edam-d exec -it <pod-name> -- /bin/bash

# Site packages (after exec)
cd /usr/bin/app/lib/python3.10/site-packages
```

**Publisher on-demand test (from inside pod):**
```python
import asyncio
from datetime import datetime, timedelta, timezone
from klaviyo.data_exchange.prep_publisher.proto.v1 import prep_publisher_pb2 as pb
from klaviyo.data_exchange.prep_publisher.server.publisher import PrepPublisher
from klaviyo.events.ingest_service.dtos.event_ingest import _create_timestamp

ingested_at = datetime.now(timezone.utc)
slo_deadline = ingested_at + timedelta(minutes=20)
events = [
    pb.EventData(
        metadata=pb.EventMetadata(
            company_id="qwerty-prep-publisher",
            source_name="source_name",
            ingested_at=_create_timestamp(ingested_at),
            slo_deadline=_create_timestamp(slo_deadline),
            priority_level=10,
        ),
        raw_payload=b"raw_payload",
        request_id="request_id",
    )
] * 10

async def main():
    for priority in [10, 20, 30]:
        publisher = PrepPublisher(priority=priority)
        await publisher.init()
        result = await publisher.publish_with_result(events)
        await publisher.stop()
        print(f"P{priority}: {result}")

asyncio.run(main())
```

---

### 3. AWS MSK Kafka Cluster

**Role:** Message broker. One topic per priority level plus retry, DLQ, offload, response, and flow-control topics.

| Topic | Description |
|-------|-------------|
| `events.public.p10-events-express-v1` | Low priority (20 min SLO) |
| `events.public.p20-events-express-v1` | Medium priority (1 min SLO) |
| `events.public.p30-events-express-v1` | High priority (5 sec SLO) |
| `events.private.offload-v1` | Throttled/shed events |
| `events.public.events-express-v1-retry-*` | Retry queues (4 delay levels, exponential backoff starting at 60s) |
| `events.private.flow-control-v1` | Flow-control signals (AIMD throttle commands) |
| `response` topic | Processor ACK/NACK back to orchestrator |

**Prod bootstrap servers:**
```
boot-t0c.kafkaeventgateway.ww49o7.c20.kafka.us-east-1.amazonaws.com:9096
boot-fok.kafkaeventgateway.ww49o7.c20.kafka.us-east-1.amazonaws.com:9096
boot-vh6.kafkaeventgateway.ww49o7.c20.kafka.us-east-1.amazonaws.com:9096
```
**Protocol:** `SASL_SSL` / `SCRAM-SHA-512` / username: `kafka-event-gateway`

**Terraform:** `~/Klaviyo/Repos/infrastructure-deployment/infrastructure/live/prod/internal-exchange/kafka-events/main.tf`

---

### 4. Events Orchestrator (k-repo / KDP)

**Role:** Kafka consumer. Pulls events into an in-memory buffer, applies final SLO prioritization, and serves batches to processors via gRPC. Uses asyncio for init/run/shutdown.

| Asset | Path |
|-------|------|
| Server source | `~/Klaviyo/Repos/k-repo/python/klaviyo/data_exchange/event_pipeline_orchestrator/server/` |
| Key files | `main.py`, `orchestrator.py`, `settings.py`, `task_state_controller/`, `buffering/`, `flow_control_protocol.py` |
| Client | `~/Klaviyo/Repos/k-repo/python/klaviyo/data_exchange/event_pipeline_orchestrator/client/main.py` |
| Appfile (prod) | `~/Klaviyo/Repos/infrastructure-deployment/apps/internal-exchange/events-orchestrator/app.yaml` |
| Appfile (rollout) | `~/Klaviyo/Repos/infrastructure-deployment/apps/internal-exchange/events-orchestrator-rollout/app.yaml` |
| Appfile (staging) | `~/Klaviyo/Repos/infrastructure-deployment/apps/internal-exchange/events-orchestrator-staging/app.yaml` |
| Terraform | `~/Klaviyo/Repos/infrastructure-deployment/infrastructure/live/prod/internal-exchange/events-orchestrator/main.tf` |
| S3 Terraform | `~/Klaviyo/Repos/infrastructure-deployment/infrastructure/live/prod/internal-exchange/events-orchestrator/s3/main.tf` |
| Server tests | `~/Klaviyo/Repos/k-repo/python/klaviyo/data_exchange/event_pipeline_orchestrator/tests/server/` |
| Client tests | `~/Klaviyo/Repos/k-repo/python/klaviyo/data_exchange/event_pipeline_orchestrator/tests/client/` |

**Scale:** StatefulSet, 90 replicas × 4 clusters = 360 pods total.
Each pod gets a globally unique index for load distribution.
**Node pool:** `event-pipeline-orchestrator`
**Prod host:** `events-orchestrator-prod.internal.clovesoftware.com`
**Statsd key:** `klaviyo.internal_exchange.event_pipeline_orchestrator`
**Memory limit:** 7 GB per pod; per-priority memory thresholds pause consumers before OOM.

**Memory thresholds (pause consumption when exceeded):**
- P10: 20% of buffer
- P20: 50%
- P30: 80%
- Offload: 30%
- Retry: 70%

**Key settings to know:**
- `number_of_replicas` — must match appfile `replicas` for unique index generation.
- `active_cluster_fleet` — used during fleet migrations (`dove` → `edam`).
- `rollout_orchestrator_config_key` — Statsig config for rollout/default pod gating.
- `enable_retry_consumer` — toggle retry topic consumption.

**Test commands (k-repo):**
```bash
# All orchestrator server tests
pants test python/klaviyo/data_exchange/event_pipeline_orchestrator/tests/server/

# Single test
pants test python/klaviyo/data_exchange/event_pipeline_orchestrator/tests/server/test_orchestrator.py -- -k test_name

# E2E test
pants test python/klaviyo/data_exchange/event_pipeline_orchestrator/tests/server/test_e2e.py
```

---

### 5. Event Pipeline Processor (app / Queue Worker)

**Role:** ASG-based queue worker that pulls batches from the Orchestrator's gRPC endpoint and executes the actual event processing logic.

| Asset | Path |
|-------|------|
| Django command | `data_exchange event_pipeline_orchestrator_runner` |
| Command source (app) | `~/Klaviyo/Repos/app/src/learning/app/data_exchange/commands/event_pipeline_orchestrator_runner.py` |
| Terraform | `~/Klaviyo/Repos/infrastructure-deployment/infrastructure/live/prod/queue-worker/event_pipeline/main.tf` |
| Terraform module | `qw_event_pipeline_orchestrator_processor` |
| ASG name | `qw/event-pipeline-orchestrator-processor` |

**Scale ASG:**
```bash
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name qw/rollout-orchestrator-processor \
  --desired-capacity 1
```

**Run processor on-demand (non-destructive — `execute=False`):**
```python
from app.data_exchange.commands.event_pipeline_orchestrator_runner import Command
cmd = Command()
cmd.run(
    execute=False,   # IMPORTANT: must be False for on-demand testing
    max_batches=10,
    max_tasks_per_batch=100,
    kafka_bootstrap_servers=(
        "boot-t0c.kafkaeventgateway.ww49o7.c20.kafka.us-east-1.amazonaws.com:9096,"
        "boot-fok.kafkaeventgateway.ww49o7.c20.kafka.us-east-1.amazonaws.com:9096,"
        "boot-vh6.kafkaeventgateway.ww49o7.c20.kafka.us-east-1.amazonaws.com:9096"
    ),
    kafka_security_protocol="SASL_SSL",
    kafka_sasl_mechanism="SCRAM-SHA-512",
    kafka_sasl_username="kafka-event-gateway",
    kafka_api_version="auto",
    kafka_retries=10,
    orchestrator_host="events-orchestrator-staging-prod.internal.clovesoftware.com",
    statsd_root="event_gateway_orchestrator_client_runner",
)
```

---

### 6. Failed Writes Processor

**Role:** Recovers events that failed to publish to MSK (secondary safety net after S3 backup).

| Asset | Path |
|-------|------|
| Appfile | `~/Klaviyo/Repos/infrastructure-deployment/apps/internal-exchange/failed-writes-processor/app.yaml` |
| Source | `~/Klaviyo/Repos/k-repo/python/klaviyo/data_exchange/prep_publisher/failed_writes_processor/` |

---

## Failure Modes & Resilience

| Failure | Behavior |
|---------|----------|
| MSK publish failure | Route to `failed-writes` topic → automated retry |
| Persistent failures | DLQ topic; then S3 for durable backup |
| Orchestrator OOM | Per-priority memory thresholds pause Kafka consumers |
| Retry queue | 4 delay levels, exponential backoff starting at 60s with 2× multiplier |
| Processor NACK with short delay (< 60s) | In-memory retry |
| Processor NACK with long delay | Re-published to retry Kafka topic |

---

## How to Work in This Codebase

- **Prefer local files first.** Read appfiles, settings, and source before suggesting changes.
- **Replica count matters.** PrepPublisher replicas × producers = MSK connections. Orchestrator replicas must match `number_of_replicas` setting.
- **Staging vs prod.** Statsig configs differ: `event_gateway_cluster_rollout_staging` vs `_prod`. Settings validator enforces `staging` in staging env-aware fields.
- **Appfile changes** in `infrastructure-deployment` trigger ArgoCD rollouts — call out when a change touches scale, env vars, node pool, or resource limits.
- **Fleet migrations.** `active_cluster_fleet` setting and `prod-edam` cluster context are relevant for orchestrator fleet work.
- **When suggesting changes**, include: file path, exact diff, test command, and any appfile/Terraform that also needs updating.

---

## Key Kubernetes Contexts & Namespaces

| Context | Use |
|---------|-----|
| `prod-edam-d` | Staging/debug pod access |
| namespace | `internal-exchange` |

---

## Useful Links

- [Architecture doc](https://klaviyo.atlassian.net/wiki/spaces/EN/pages/4909891917/Event+Gateway+fka+Event+Pipeline+2025)
- [Incident Runbook](https://klaviyo.atlassian.net/wiki/spaces/EN/pages/4577689613/Event+Gateway+fka+Event+Pipeline+2025+Runbook)
- [Kafka Runbook](https://klaviyo.atlassian.net/wiki/spaces/EN/pages/5019533498/Event+Gateway+Kafka+Runbook)
- [Mission Control Dashboard](http://grafana.klaviyodevops.com:3000/d/nQcZjs7Nk/event-pipeline-mission-control?orgId=1)
- [Eng Blog Post](https://klaviyo.tech/rebuilding-event-infrastructure-at-scale-bebfe764bd8f)
