
---
name: kdev-event-gateway
description: Agent context for developing on the Event Gateway (fka Event Pipeline 2025). Teaches navigation of architecture, metrics, and controls — always read local files to discover current state rather than relying on hardcoded values.
user-invocable: true
disable-model-invocation: false
allowed-tools: Read, Glob, Grep, Bash, Skill, mcp__plugin_context7_context7__resolve-library-id, mcp__plugin_context7_context7__query-docs
model: sonnet
---

You are helping me work on Klaviyo's **Event Gateway** codebase.
**Always read local files first.** Metrics names, topic names, settings, and Statsig keys change — find the current truth by reading the code, not by guessing.

Before helping write or review a PR description, check for `.github/pull_request_template.md` in the relevant repo and follow its structure.

---

## Repos

| Name | Path |
|------|------|
| app (monolith) | `~/Klaviyo/Repos/app` |
| k-repo (KDP services) | `~/Klaviyo/Repos/k-repo` |
| infra (appfiles, Terraform) | `~/Klaviyo/Repos/infrastructure-deployment` |
| handbook | `~/Klaviyo/Repos/eng-handbook` |

---

## System Overview

The **Event Gateway** is a priority-aware, Kafka-backed ETL buffer in front of the Event Pipeline. It ingests ~100B events/month, classifies them by SLO priority, and fans them to downstream processors asynchronously.

**Data flow:**
```
Event source
  → IngestService (app)             — classify by SLO priority, schedule
  → PrepPublisher (k-repo / KDP)    — gRPC proxy; publish to correct Kafka topic
  → AWS MSK / KRaft (4 clusters)    — broker; priority + retry + DLQ + offload topics
  → Events Orchestrator (k-repo)    — Kafka consumer; in-memory buffer; task state; gRPC server
  → Event Pipeline Processor (app)  — queue worker; fetches batches; executes
```

**Priority levels** (set by IngestService classifier):
| Level | SLO     | Use case |
|-------|---------|----------|
| P30   | < 5 sec | High-priority (e.g. Flow Triggers) |
| P20   | < 1 min | Medium priority |
| P10   | < 20 min| Low priority (bulk/background) |

---

## Component Navigation

For each component below, the sections tell you **where to navigate** to understand its current architecture, **where metrics are emitted**, and **where controls (hot settings / Statsig gates) live**. Read the code — don't assume values are current.

---

### 1. IngestService (app repo)

**Role:** Accepts raw events, runs static and dynamic classification, applies quota/delay via scheduler, then publishes to PrepPublisher over gRPC.

#### Navigate to

| What | Where |
|------|-------|
| Service root | `~/Klaviyo/Repos/app/src/learning/app/services/events/ingest/service/` |
| Entry / base class | `base.py` |
| Static classifier | `classifier/static.py` — tags events by type (realtime, purpose) |
| Dynamic classifier | `classifier/dynamic.py` — checks quotas & capacity |
| Scheduler | `scheduler.py` — delay logic before handoff |
| SLO service | `slo_service.py` — AIMD congestion control for P10 backpressure |
| Publisher (outbound) | `~/Klaviyo/Repos/app/src/learning/app/data_exchange/event_ingest_publisher.py` |
| Tests | `~/Klaviyo/Repos/app/tests/services/events/ingest/service/` |

To understand the full classification pipeline, read `base.py` first — it wires together static classifier → dynamic classifier → scheduler → publisher.

#### Metrics

Read `slo_service.py` — it emits the AIMD congestion-decrease counter that is the primary SLO health signal (alert threshold: >10/min sustained). For the full list of metrics, read the source files and look for `statsd` call sites directly.

#### Controls

- **Hot settings:** look for `hot_settings.py` in the service root and any references to `HotSetting` across the service directory.
- **Statsig gates:** look for `check_gate` or `get_config` calls in the service directory.
- Current hot settings file: `hot_settings.py` in the service root.

---

### 2. PrepPublisher (k-repo / KDP)

**Role:** gRPC service that acts as the Kafka producer proxy. Each pod maintains one producer per priority (p10, p20, p30, offload) plus optional rollout-cluster producers. Routes events to the correct MSK topic by priority level.

#### Navigate to

| What | Where |
|------|-------|
| Server root | `~/Klaviyo/Repos/k-repo/python/klaviyo/data_exchange/prep_publisher/server/` |
| Entry point | `main.py` — sets up gRPC server, initializes Statsig |
| Request router | `router.py` — `PublishEvents` RPC; per-company rollout routing via CRC32 hash |
| Kafka producer | `publisher.py` — wraps aiokafka; failure handling; statsd emission |
| Settings | `settings.py` — topic names, Kafka config, runtime environment enum |
| Rollout gating | `gating.py` — Statsig dynamic config read; `get_rollout_config()` |
| Client | `~/Klaviyo/Repos/k-repo/python/klaviyo/data_exchange/prep_publisher/client/` |
| Appfile (prod) | `~/Klaviyo/Repos/infrastructure-deployment/apps/internal-exchange/prep-publisher/app.yaml` |
| Appfile (staging) | `~/Klaviyo/Repos/infrastructure-deployment/apps/internal-exchange/prep-publisher-staging/app.yaml` |
| Server tests | `~/Klaviyo/Repos/k-repo/python/klaviyo/data_exchange/prep_publisher/tests/server/` |
| Client tests | `~/Klaviyo/Repos/k-repo/python/klaviyo/data_exchange/prep_publisher/tests/client/` |

Read `settings.py` for the canonical topic names and `router.py` for how rollout percentage and company-ID hashing determine cluster routing.

#### Metrics

Read `publisher.py` and `router.py` for statsd call sites. Key signals to look for: `publish_failed.<ErrorType>`, rollout routing counters in `router.py`, and producer latency timers in `publisher.py`.

The statsd base key is constructed from `settings.runtime_environment.statsd_key_prefix` — read `settings.py` → `RuntimeEnvironment` enum to see the prefix for each environment.

#### Controls

- **Statsig dynamic config:** `gating.py` — `get_rollout_config(config_key)` controls which cluster traffic rolls to and what percentage.
- **Config keys:** set via env var in the appfile (`KL_PREP_PUBLISHER_ROLLOUT__CLUSTER_ROLLOUT_CONFIG_KEY`) — read the appfile for the current key name per environment.
- **No hot settings** in PrepPublisher — all runtime control goes through Statsig dynamic config.

---

### 3. MSK Kafka Cluster (KRaft)

**Role:** Message broker. Multiple clusters (prod and rollout). One topic per priority level plus offload, retry, DLQ, response, and flow-control topics. Runs in KRaft mode (no ZooKeeper).

#### Navigate to

| What | Where |
|------|-------|
| MSK Terraform | `~/Klaviyo/Repos/infrastructure-deployment/infrastructure/live/prod/internal-exchange/kafka-events/main.tf` |
| Topic names (source of truth) | `~/Klaviyo/Repos/k-repo/python/klaviyo/data_exchange/prep_publisher/server/settings.py` — `PrepPublisherKafkaProducerSettings` |
| Consumer topic names | `~/Klaviyo/Repos/k-repo/python/klaviyo/data_exchange/event_pipeline_orchestrator/server/settings.py` — `KafkaSettings` |
| Bootstrap servers | Read the appfile for each component (`KL_*_KAFKA__BOOTSTRAP_SERVERS` env var) — never hardcode |

To understand the full topic topology (p10/p20/p30, offload, retry levels, DLQ, response, flow-control), read both `settings.py` files above side by side. Topic names in the producer settings must match those in the consumer settings.

#### Key concepts

- **4 clusters** in prod: primary + rollout target. Rollout is managed by Statsig config in PrepPublisher and Orchestrator.
- **Retry topics** use a leveled delay scheme (e.g. N levels × backoff multiplier). Read `RetryQueuesSettings` in orchestrator `settings.py` for current level count and delay values.
- **Offload topic** handles events throttled by AIMD / capacity management — they re-enter the pipeline later.
- **Flow-control topic** carries AIMD signals from the orchestrator back to the ingest layer.
- Connection count = (PrepPublisher replicas) × (producers per pod). Read the appfile HPA config before changing replica counts.

---

### 4. Events Orchestrator (k-repo / KDP)

**Role:** StatefulSet Kafka consumer. Pulls events from priority topics into an in-memory buffer, applies final SLO-based prioritization via the task state controller, and serves batches to processors over gRPC. Each pod is assigned a unique index for load distribution.

#### Navigate to

| What | Where |
|------|-------|
| Server root | `~/Klaviyo/Repos/k-repo/python/klaviyo/data_exchange/event_pipeline_orchestrator/server/` |
| Entry point | `main.py` — asyncio loop, Statsig init, statsd key construction |
| Top-level orchestrator | `orchestrator.py` — wires consumers, buffer, task state, gRPC service |
| Settings | `settings.py` — all Kafka config, memory thresholds, retry settings, env-aware validation |
| Kafka consumers | `broker/` — consumer setup, partition assignment, per-priority consumers |
| In-memory buffer | `buffering/` — event buffer, memory tracking per priority |
| Task state controller | `task_state_controller/` — final priority ordering, lease management, expired task requeue |
| Load distribution | `distribution/` — globally unique index generation across replicas |
| Flow control | `flow_control_protocol.py` — AIMD signals, capacity decrease/increase logic |
| Rollout gating | `gating.py` — Statsig gate for rollout vs default pod behavior |
| Client | `~/Klaviyo/Repos/k-repo/python/klaviyo/data_exchange/event_pipeline_orchestrator/client/main.py` |
| Appfile (prod) | `~/Klaviyo/Repos/infrastructure-deployment/apps/internal-exchange/events-orchestrator/app.yaml` |
| Appfile (rollout) | `~/Klaviyo/Repos/infrastructure-deployment/apps/internal-exchange/events-orchestrator-rollout/app.yaml` |
| Appfile (staging) | `~/Klaviyo/Repos/infrastructure-deployment/apps/internal-exchange/events-orchestrator-staging/app.yaml` |
| Node pool config | `~/Klaviyo/Repos/infrastructure-deployment/infrastructure/kubernetes/fleets/edam/prod-edam.yaml` |
| Server tests | `~/Klaviyo/Repos/k-repo/python/klaviyo/data_exchange/event_pipeline_orchestrator/tests/server/` |
| Client tests | `~/Klaviyo/Repos/k-repo/python/klaviyo/data_exchange/event_pipeline_orchestrator/tests/client/` |

Start in `orchestrator.py` to understand the top-level wiring. Then go deeper into `task_state_controller/` for prioritization logic and `buffering/` for memory management.

#### Consumers & Priorities

The orchestrator runs parallel consumers for p10, p20, p30, offload, and retry topics. Each has its own `max_records` fetch limit and memory threshold — read `KafkaSettings` and `memory_percentage_threshold_p*` fields in `settings.py` for current values. When a threshold is exceeded, that consumer pauses to prevent OOM.

The **task state controller** does the final ordering: it sorts the in-memory buffer by SLO deadline and serves highest-urgency batches first regardless of which topic an event came from.

#### Metrics

Read the server source files for statsd call sites. Key signals: buffer memory usage per priority, task lease expirations, batch size served, consumer pause/resume events, flow-control decrease/increase counters.

The statsd base key is `klaviyo.internal_exchange.event_pipeline_orchestrator` + a unique per-pod suffix. Read `main.py` → `_customize_statsd_base_name()` for how the suffix is built.

#### Controls

- **Statsig:** `gating.py` — `rollout_orchestrator_config_key` in settings controls whether this pod is a rollout or default orchestrator. Read the appfile env var for the current key.
- **Settings flags to check:**
  - `enable_retry_consumer` — toggles retry topic consumption
  - `enable_explicit_retry_partition_management` — toggles manual vs dynamic partition assignment for retry topics
  - `active_cluster_fleet` — used during fleet migrations
  - `number_of_replicas` — must match appfile `replicas` for correct index generation; mismatch causes duplicate IDs

---

### 5. Event Pipeline Processor (app / Queue Worker)

**Role:** ASG-based EC2 queue workers that connect to the Orchestrator gRPC endpoint, pull batches of events, and execute the actual processing logic (the domain-specific work).

#### Navigate to

| What | Where |
|------|-------|
| Django command | `~/Klaviyo/Repos/app/src/learning/app/data_exchange/commands/event_pipeline_orchestrator_runner.py` |
| Django command name | `data_exchange event_pipeline_orchestrator_runner` |
| Terraform | `~/Klaviyo/Repos/infrastructure-deployment/infrastructure/live/prod/queue-worker/event_pipeline/main.tf` |
| Terraform module | `qw_event_pipeline_orchestrator_processor` |

Read the Terraform module to understand instance type, ASG sizing, and the full command invocation (bootstrap servers, orchestrator host, etc.). Those values are the source of truth for prod config.

#### Metrics

Read `event_pipeline_orchestrator_runner.py` and the orchestrator client in k-repo for statsd call sites.

#### Controls

- **Hot settings / feature gates** in the processor live in the app repo's domain-specific processing code (not in the runner itself). If you're working on processor behavior, check the specific processor class for hot settings.
- **ASG capacity** is the primary operational control — scaling the ASG is how throughput is adjusted.

---

### 6. Failed Writes Processor (k-repo / KDP)

**Role:** Recovers events that PrepPublisher failed to publish to MSK. Reads from a failed-writes topic and retries; persistent failures go to DLQ or S3.

| What | Where |
|------|-------|
| Source | `~/Klaviyo/Repos/k-repo/python/klaviyo/data_exchange/prep_publisher/failed_writes_processor/` |
| Appfile | `~/Klaviyo/Repos/infrastructure-deployment/apps/internal-exchange/failed-writes-processor/app.yaml` |

---

## Handy Scripts & Testing

### Run app (IngestService / Processor) tests
```bash
klaviyocli docker setup   # one-time auth

# Full test file
make TEST="tests/services/events/ingest/service/test_base.py" docker-unit

# Single test
make TEST="tests/services/events/ingest/service/test_base.py::Class::test_name" docker-unit
```

### Run k-repo (PrepPublisher / Orchestrator) tests
```bash
# PrepPublisher server tests
LOG_LEVEL=info pants test python/klaviyo/data_exchange/prep_publisher/tests/server/test_main.py

# PrepPublisher single test
pants test python/klaviyo/data_exchange/prep_publisher/tests/server/test_router.py -- -k test_name

# Orchestrator all server tests
pants test python/klaviyo/data_exchange/event_pipeline_orchestrator/tests/server/

# Orchestrator single test
pants test python/klaviyo/data_exchange/event_pipeline_orchestrator/tests/server/test_orchestrator.py -- -k test_name
```

### Debug a PrepPublisher staging pod
```bash
# Find the pod
kubectl get pods -n internal-exchange --context prod-edam-d -l app=prep-publisher-staging-prod

# Exec in
kubectl -n internal-exchange --context prod-edam-d exec -it <pod-name> -- /bin/bash

# Navigate to site packages
cd /usr/bin/app/lib/python3.10/site-packages
```

### Inspect PrepPublisher config and Statsig from inside a pod
```python
import os
from klaviyo.internal_experimentation.kstatsig import ForkSafeStatsig
from klaviyo.data_exchange.prep_publisher.server.gating import get_rollout_config
from klaviyo.data_exchange.prep_publisher.server.main import get_settings
from klaviyo.core.monitoring import get_statsd_key
from klaviyo.core.monitoring.src import setup_statsd

settings = get_settings()
base_statsd_key = f"klaviyo.data_exchange.{settings.runtime_environment.statsd_key_prefix}"
setup_statsd(statsd_base_key_name=base_statsd_key)

print(base_statsd_key)
print(get_statsd_key("publisher"))

ForkSafeStatsig.initialize(
    statsig_server_sdk_key=os.environ.get("STATSIG_SDK_KEY"),
    use_production_statsig_env=True,
)

# Read current rollout config — get key name from appfile env var
config = get_rollout_config("event_gateway_cluster_rollout_staging")
print(config)
```

### Publish test events from a PrepPublisher pod
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

### Publish test events from IngestService (app on-demand)
```python
from app.data_exchange.event_ingest_publisher import EventIngestPublisher, EventIngest

publisher = EventIngestPublisher()
cid = "V3qGae"  # test company_id
event_ingest = EventIngest(company_id=cid, statistic_key="api")
publisher._publish_payloads_with_client(
    client=publisher._client,
    client_name=publisher.ClientName.PRODUCTION,
    company_id=cid,
    event_payloads=[event_ingest],
    use_fallbacks=False,
)
```

### Run the processor on-demand (non-destructive)
```python
# IMPORTANT: execute=False — reads from Kafka but does not process events
from app.data_exchange.commands.event_pipeline_orchestrator_runner import Command

cmd = Command()
cmd.run(
    execute=False,
    max_batches=10,
    max_tasks_per_batch=100,
    # Get bootstrap_servers and orchestrator_host from Terraform:
    # ~/Klaviyo/Repos/infrastructure-deployment/infrastructure/live/prod/queue-worker/event_pipeline/main.tf
    kafka_bootstrap_servers="...",
    kafka_security_protocol="SASL_SSL",
    kafka_sasl_mechanism="SCRAM-SHA-512",
    kafka_sasl_username="kafka-event-gateway",
    kafka_api_version="auto",
    kafka_retries=10,
    orchestrator_host="events-orchestrator-staging-prod.internal.clovesoftware.com",
    statsd_root="event_gateway_orchestrator_client_runner",
)
```

### Scale the processor ASG
```bash
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name qw/rollout-orchestrator-processor \
  --desired-capacity <N>
```

---

## Using Glean Code Skills

When local file inspection isn't enough, use `/glean-code` sub-skills via the `Skill` tool:

| Sub-skill | When to use |
|-----------|-------------|
| `glean-code:codebase-context` | Need a high-level map of how a system fits together (e.g. "how does the full ingest pipeline work end-to-end?") |
| `glean-code:find-examples` | Looking for real usage of an internal API or pattern across the org (e.g. how other services use `aiokafka`, how retry decorators are applied) |
| `glean-code:code-owners` | Need to know who maintains a component before sending a PR or asking for a review (e.g. "who owns the MSK Terraform?", "who reviews prep-publisher changes?") |
| `glean-code:similar-code` | Want to model a change on existing implementations (e.g. "show me how other KDP services handle Kafka consumer backpressure") |

Prefer reading local files directly when you already know the path. Use glean when you don't know where something lives, need cross-repo context, or want to find owners.

---

## Working Principles

- **Read settings.py and appfiles before answering config questions.** Topic names, bootstrap servers, memory thresholds, and replica counts are all there — don't guess.
- **Appfile changes flow through ArgoCD.** Call out when a proposed change touches replica count, resource limits, env vars, or node pool.
- **Replica count has side effects.** PrepPublisher replicas × producers = MSK connections. Orchestrator replicas must match the `number_of_replicas` setting or pod IDs collide.
- **Staging vs prod is enforced in code.** The orchestrator settings validator (`EnvAwareField`) will reject prod configs in staging — read `settings.py` to understand the rules.
- **When adding metrics,** read existing statsd call sites in the file you're editing first to follow the established naming convention.
- **When adding a Statsig gate,** read `gating.py` in the relevant service to see the existing gate/config pattern and initialization lifecycle.

---

## Incident Response

Reference resources during an incident:
- **Dashboard:** [Event Pipeline Mission Control](http://grafana.klaviyodevops.com:3000/d/nQcZjs7Nk/event-pipeline-mission-control?orgId=1)
- **Runbook:** [Event Pipeline 2025 Runbook](https://klaviyo.atlassian.net/wiki/spaces/EN/pages/4577689613/Event+Gateway+fka+Event+Pipeline+2025+Runbook)
- **Kafka Runbook:** [MSK Operations](https://klaviyo.atlassian.net/wiki/spaces/EN/pages/5019533498/Event+Gateway+Kafka+Runbook)

When helping triage an incident: always ask which scenario matches, pull the dashboard first, and check logs/pod state before recommending action.

---

### Scenario 1 — Primary topic poll delay > 1 min for 5+ min
**Risk:** High | **Component:** Events Orchestrator

Events are not being consumed from priority (p10/p20/p30) topics fast enough. May breach SLOs (P30 < 5s, P20 < 1min, P10 < 20min).

**Triage steps:**
1. Check the orchestrator Grafana board — is this pod-specific or fleet-wide?
2. **Pod-specific:** check pod health (Argo UI, kubectl). If unhealthy, restart affected pods.
3. **Fleet-wide:** suspect Kafka MSK connectivity. Primary topics share a cluster with retry and response topics — if connectivity is broken, all consumption is affected.
4. If pods remain unhealthy after restart, engage SRE. Loop in the Events team.
5. **Setting lever:** increase `max_records_p30`, `max_records_p20`, `max_records_p10` in orchestrator `settings.py` to fetch larger batches per poll. Read current values before changing.
   - Path: `~/Klaviyo/Repos/k-repo/python/klaviyo/data_exchange/event_pipeline_orchestrator/server/settings.py` → `KafkaSettings`
6. **Last resort:** manually scale orchestrator replicas — risky, multi-step, requires a second team member and Events team sign-off.
   - Scenario-specific runbook: https://klaviyo.atlassian.net/wiki/spaces/EN/pages/5091360942/Scenario+Max+Poll+Delay+alert+on+the+primary+priority+topics

---

### Scenario 2 — Orchestrator pod count ≠ 360
**Risk:** High | **Component:** Events Orchestrator

Missing pods = uncovered Kafka partitions = processing delays for events on those partitions. SLO violations possible at scale.

**Triage steps:**
1. Check Grafana — how many pods are affected? (Drops in multiples of 90 = one full cluster; may be a Grafana glitch.)
2. Find affected pods via Argo UI.
3. **One cluster affected:** likely a node failure. Check EC2 autoscaling group for that cluster.
   - If the old node is terminating naturally, you can wait.
   - If stuck, manually delete the affected pods to force rescheduling on a healthy node.
4. **Pods failing to start:** check logs for crash cause (bad config, code regression). If a recent deploy is implicated, prepare a revert PR.
5. **During BFCM:** code changes should not be happening — focus on infrastructure (node health, ASG).
6. If all options exhausted, page SRE via Paved Path.

---

### Scenario 3 — > 1k PrepPublisher publish errors in 5 min
**Risk:** High | **Component:** PrepPublisher

Events failing to publish to primary Kafka cluster. Fallback chain: GP-03 cluster → S3. Data loss is possible in the worst case.

**Triage steps:**
1. Check failed-writes dashboard immediately — where are failed events going?
2. Check Sentry for exception types from prep-publisher.
3. Check Splunk logs for PrepPublisher to understand failure reason.
   - Log link in appfile: `~/Klaviyo/Repos/infrastructure-deployment/apps/internal-exchange/prep-publisher/app.yaml` → `logs`
4. **High volume cause:** consider scaling out PrepPublisher pods (HPA max is in the appfile).
5. **Events on GP-03 (fallback cluster):** Failed Writes Processor should retry automatically — check its dashboard.
6. **Events on S3:** require manual republish using the script in the runbook. Do not skip this step.

---

### Scenario 4 — Publish latency > percentile threshold for 5 min
**Risk:** High | **Component:** PrepPublisher / MSK

Event ingestion is delayed — SLO risk.

**Triage steps:**
1. **High load (expected during BFCM):** if MSK cluster and pods are healthy, this may be transient — monitor.
2. **MSK cluster issue:**
   - Check broker/cluster health in Grafana and AWS MSK console.
   - MSK broker scaling is possible but manual and should be avoided — loop in the MSK team.
3. **Pod issue:**
   - Check PrepPublisher pod health in Grafana, Argo UI, kubectl.
   - Restart unhealthy pods.
   - Page SRE if pods cannot be recovered.

---

### Scenario 5 — Response topic poll delay > 1 min for 5+ min
**Risk:** High | **Component:** Events Orchestrator

Processor ACK/NACKs are not being consumed fast enough. Completed tasks will appear to expire, causing the orchestrator to retry already-processed events — increasing memory pressure, fetch latency, and downstream duplication.

**Triage steps:**
1. Check Grafana — pod-specific or fleet-wide?
2. **Pod-specific:** restart unhealthy pods.
3. **Fleet-wide:** suspect MSK connectivity. The response topic shares a cluster with primary and retry topics — if broken, task ingress is also likely affected.
4. **Setting lever:** bump `max_poll_records` on the response topic consumer.
   - Path: `~/Klaviyo/Repos/k-repo/python/klaviyo/data_exchange/event_pipeline_orchestrator/server/settings.py` → `ResponseTopicSettings`
5. **Last resort:** scale out orchestrator replicas (same caveats as Scenario 1).
6. Could also be MSK-side latency — see Scenario 4.

---

### Scenario 6 — Mean fetch task batch latency > 1 sec for 2+ min
**Risk:** High | **Component:** Events Orchestrator → Processor handoff

Processors are slow to get batches from the orchestrator — total processing time increases, SLO risk.

**Triage steps:**
1. **Monitor:** asyncio task lag per orchestrator pod AND client-side latency. Focus on lag, not total task count.
2. **High lag on a few pods:**
   - May be a temporary backlog — acceptable if not sustained.
   - If sustained: restart the affected pods and monitor task redistribution.
3. **High lag on most/all pods:**
   - Check CPU usage across the orchestrator fleet.
   - **High CPU:** the backlog is overwhelming pods. As an extreme measure, lower the per-priority memory thresholds in `settings.py` to pause Kafka consumption sooner and keep the in-memory backlog smaller.
     - `memory_percentage_threshold_p10/p20/p30/offload` in `EventPipelineOrchestratorSettings`
   - **Normal CPU:** suspect a KDP platform issue. Escalate to the KDP SRE team.

---

### Scenario 7 — Sentry: RequestTimedOutError, KafkaConnectionError, SystemExit, etc.
**Risk:** Medium | **Component:** Varies

Many Sentry errors are transient at low volume — but not all. Treat `#sentry-critical` alerts with higher urgency.

**Triage steps:**
1. **Always** pull up the dashboard first to confirm whether there is observable functional degradation.
2. If the system metrics look healthy and errors are low-frequency, monitor until the issue subsides.
3. If errors are high-frequency or trending up, correlate with Scenario 1–6 above.
4. If a specific error class is expected at low rates, consider archiving in Sentry with a threshold rather than leaving it open.

---

## Useful Links

- [Architecture doc](https://klaviyo.atlassian.net/wiki/spaces/EN/pages/4909891917/Event+Gateway+fka+Event+Pipeline+2025)
- [Incident Runbook](https://klaviyo.atlassian.net/wiki/spaces/EN/pages/4577689613/Event+Gateway+fka+Event+Pipeline+2025+Runbook)
- [Kafka Runbook](https://klaviyo.atlassian.net/wiki/spaces/EN/pages/5019533498/Event+Gateway+Kafka+Runbook)
- [Mission Control Dashboard](http://grafana.klaviyodevops.com:3000/d/nQcZjs7Nk/event-pipeline-mission-control?orgId=1)
- [Eng Blog Post](https://klaviyo.tech/rebuilding-event-infrastructure-at-scale-bebfe764bd8f)
- [Poll Delay Scenario Runbook](https://klaviyo.atlassian.net/wiki/spaces/EN/pages/5091360942/Scenario+Max+Poll+Delay+alert+on+the+primary+priority+topics)
