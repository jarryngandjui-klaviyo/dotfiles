
---
name: kdev-generic
description: Explains Klaviyo code using local context first, with visual mental models and concrete examples.
---

You are helping me work on Klaviyo’s **Event Gateway** locally.

The **Event Gateway** is a queuing system that asynchronously accepts event data from various sources in front of the **Event Pipeline** (which debounces, hydrates, and records events in different formats).

Before making architectural or behavioral assumptions, review this document:  
[https://klaviyo.atlassian.net/wiki/spaces/EN/pages/4909891917/Event+Gateway+fka+Event+Pipeline+2025](https://klaviyo.atlassian.net/wiki/spaces/EN/pages/4909891917/Event+Gateway+fka+Event+Pipeline+2025)

### Core concepts

- **Priority-based consumption:** `p10`, `p20`, `p30`, `offload`  
    These priorities show up in topic naming, routing, and consumption behavior across the system.

### Event Gateway architecture components

In this context, an **Appfile** refers to a Kubernetes deployment configuration. If you need more detail on Appfiles or KDP, consult the eng‑handbook (for example, `eng-handbook/kubernetes/new_platform/appfiles.md`).

#### Event Classifier

- **Description:**  
    Lightweight component at the very front of the flow that classifies incoming events as **P10 (low priority)**, **P20**, or **P30 (high priority)** using a combination of static and dynamic rules owned by the Events team.
- **Notes for Claude:**  
    Treat classifier output as the canonical source of event priority. Do not assume priorities are arbitrary tags; they drive topic selection and downstream scheduling.

#### Event Ingest Service

- **Description:**  
    Service in `app` responsible for getting events from app into the primary Kafka cluster (MSK), primarily via the **PrepPublisherClient**. It can also fall back to an alternate Kafka cluster (GP‑3) or S3 if necessary.
- **Source dir:**  
    `app/src/learning/app/data_exchange/event_ingest_publisher.py`

#### PrepPublisherClient

- **Description:**  
    Client library that runs inside the `app` monolith. It is responsible for delivering events to the **primary MSK Kafka cluster** by talking to **PrepPublisher** (the gRPC proxy). If the primary path fails, it can route to:
    - An alternative Kafka cluster (`gp-01`/GP‑3), or
    - S3 as a final fallback.
- **Artifacts:**
    - Code lives in **k‑repo**, but the client runs in `app`.

#### PrepPublisher (Event Publisher / Kafka Publisher Proxy)

- **Description:**  
    A lightweight **gRPC service** that acts as a Kafka Publisher Proxy for the Event Gateway. It receives events from clients (e.g., Event Ingest Service via PrepPublisherClient) and routes them to the appropriate Kafka topics. Each pod maintains a routing configuration that maps events to topics for each priority (`p10`, `p20`, `p30`, `offload`).
- **Resilience / behavior:**
    - Publishes to **primary MSK Express cluster** for events.
    - If publishing to primary fails, it attempts an alternate Kafka cluster.
    - If both clusters are unavailable, it writes events to **S3** as a final fallback.
- **Tips:**
    - **Replica count directly affects the number of active connections** to the MSK cluster. When proposing scaling changes, consider connection saturation and MSK limits.
- **Appfile:**  
    `infrastructure-deployment/apps/internal-exchange/prep-publisher/app.yaml`
- **Server code dir (k‑repo):**  
    `k-repo/python/klaviyo/data_exchange/prep_publisher/server/`

---

### Kafka Buffer (MSK Express cluster)

- **Description:**  
    The Kafka-based buffer layer for Event Gateway traffic, running on an **AWS MSK Express** cluster dedicated to events.
- **Topics and priorities:**
    - Primary topics for each priority level: **P30**, **P20**, **P10**.
    - A set of **retry topics** to support multi-stage retries and exponential backoff.
    - A **Dead Letter Queue (DLQ)** for permanently failed events.
- **Partitioning model:**
    - Each primary and retry topic has **360 partitions** (DLQ is the main exception).
    - The **Events Orchestrator** scaling model is tightly coupled to this: 360 orchestrator pods, 1 pod per partition.
- **Write distribution:**
    - Partition assignment for writes currently uses **round-robin** distribution across partitions.
- **Terraform path (infra for Kafka buffer):**  
    `infrastructure-deployment/infrastructure/live/prod/internal-exchange/events-orchestrator/kafka-express.tf`
- **Operational pointers (for debugging):**
    - Kafka UI / bastion, CloudWatch/Chronosphere dashboards, and AWS MSK console links are in the Confluence doc; use those for lag and health investigations.

---

### Events Orchestrators

These are the core Kafka consumers for the Event Gateway, built as StatefulSets on KDP.

- **High-level description:**  
    Kafka consumers that read from Event Gateway Kafka topics (P30/P20/P10, retry topics) and coordinate event processing. Designed to run **360 replicas** to achieve a **1 pod : 1 partition** mapping across priority topics.
- **Tips:**
    - Implemented as a **StatefulSet** running in a dedicated node pool `event-pipeline-orchestrator` with capped capacity.
    - Any change to:
        - **Partition counts**, or
        - **Replica counts / pod mapping**  
            must honor the 1:1 partition-to-pod assumption and the manual partition assignment logic.
- **Appfile:**  
    `infrastructure-deployment/apps/internal-exchange/events-orchestrator/app.yaml`
- **Node pool definition:**  
    `infrastructure-deployment/infrastructure/kubernetes/fleets/edam/prod-edam.yaml`
- **Server code dir (k‑repo):**  
    `k-repo/python/klaviyo/data_exchange/event_pipeline_orchestrator/server/`
- **Client source code (Event Pipeline client in k‑repo):**  
    `k-repo/python/klaviyo/data_exchange/event_pipeline_orchestrator/client/main.py`

##### Orchestrator internal components

Understanding these is important when changing behavior or debugging:

1. **Kafka Consumer Manager**
    
    - Priority-aware consumer over **P10/P20/P30** topics and **retry topics**.
    - Manages:
        - Fetching from priority + retry topics (including delayed retries using `delay_until`).
        - Publishing failed tasks to appropriate **retry topics** or **DLQ**.
        - **Offset management** (out-of-order, safe commit points per topic-partition).
        - **Manual partition assignment** based on pod identifiers (avoids consumer-group rebalancing).
        - **Throttling** to prevent the in-memory buffer from overflowing (memory-aware consumption).
2. **Task State Controller**
    
    - Maintains an in‑memory map of tasks and their lease/expiration.
    - Performs **final prioritization** based on `group_key` and `slo_deadline`.
    - Imports tasks from Kafka Consumer Manager and **exports prioritized batches** to gRPC clients.
    - Handles ACK/NACK responses, including:
        - In‑memory short-delay retries.
        - Delegating longer delays to Kafka via the Consumer Manager.
    - Coordinates with the Consumer Manager to commit Kafka offsets when it’s safe.
3. **gRPC Server**
    
    - gRPC interface between the Orchestrator and downstream **Event Processor Consumers**.
    - Responsibilities:
        - Accept task-batch requests from Event Pipeline clients.
        - Consume responses from the Kafka **response topic**.
        - Use a `source_id` scheme to ensure responses are routed back to the correct orchestrator pod.

---

### Event Pipeline Processors (Event Processor Consumers)

- **Description:**  
    Queue-worker / ASG-based components that actually execute event processing work after tasks are handed off by the orchestrator. These run in the **queue-worker (QW)** stack, not KDP.
- **Terraform path (QW infra):**  
    `infrastructure-deployment/infrastructure/live/prod/queue-worker/event_pipeline/main.tf`
- **Terraform module name:**  
    `qw_event_pipeline_orchestrator_processor`
- **Processor source (app):**
    - Executed via a Django/QW management command, typically at:  
        `app/src/learning/app/events/services/process/ingest/executor.py`
    - Uses an Event Pipeline client library from k‑repo to:
        - Fetch task batches over gRPC from the Orchestrator.
        - Process events.
        - Publish responses to the Kafka **response topic**.

When investigating QW behavior, inspect:

- The executor code, and
- Any Event Pipeline client configuration in k‑repo referenced by that executor.

---

### How Claude Code should use this context

When using this prompt in Claude Code, ensure it:

- **Reads the Confluence doc** for architectural details and invariants before proposing changes.
    
- Uses the listed **paths (Appfiles, Terraform, code dirs)** as the **source of truth** for:
    
    - Where services run (KDP vs QW).
    - How Kafka topics/partitions are defined.
    - How deployment is wired.
- **Respects key invariants:**
    
    - Priority model (`p10/p20/p30/offload`) as a core scheduling and routing primitive.
    - **1:1 pod-to-partition** design for the Orchestrator and the 360-partition layout.
    - Manual partition assignment and the retry/DLQ patterns.
- **When suggesting changes**, always:
    
    - Call out any implications for:
        - Topic/partition counts,
        - Orchestrator replica counts,
        - MSK cluster configuration, or
        - QW executor behavior.
    - Provide concrete file paths and example commands (tests, validation, or deployment) tied to the repos above.

(Use Glean Document Reader for the URL mentioned above when you need to pull the latest version of the Confluence doc.)