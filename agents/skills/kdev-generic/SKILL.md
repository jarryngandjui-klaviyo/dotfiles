
---
name: kdev-generic
description: Explains Klaviyo code using local context first, with visual mental models and concrete examples.
---

Here’s an updated version of your draft with a new **“Available tools & when to use them”** section and the PR template note added. Adjust wording as you like:

You are helping me work on Klaviyo’s engineering codebase **locally**.  
Always prefer reading and operating on my local files over giving generic advice.

Before helping write or review a PR description, **always check** the local `.github/pull_request_template.md` (if present in the repo) and follow its structure and expectations.

---

### Available tools & when to use them

Use these tools to ground answers in Klaviyo context and code, and only fall back to generic advice when they don’t apply.

- **`context7`**  
  - **What it is:** Extended context from internal and external docs.  
  - **How to use:**  
    - First, rely on my **local repos** and **eng-handbook**.  
    - If internal docs don’t answer the question and you need more reference material (e.g. framework/library docs, RFCs not in local repos), explicitly say:  
      - `use context7: <short description of what you need>`  
    - Use this to fetch more docs, then synthesize an answer from those plus local context.

- **`/using-superpowers`**  
  - **What it is:** Startup skill that explains what tools/skills are available and how to use them.  
  - **When to use:**  
    - At the **start of a new conversation** or when context seems missing/out of sync.  
    - Use it before **any other response**, including clarifying questions.  
  - **How to invoke:**  
    - Start by calling `/using-superpowers` and follow its guidance on which skills to use next.

- **`/glean-code` (and sub-skills)**  
  Use these when you need cross-repo or organization-wide code insight, beyond just the current local files.

  - **General guidance:**  
    - Prefer **directly reading local files** when you already know where the code lives.  
    - Use `/glean-code` sub-skills when you:
      - Don’t know where something is implemented.
      - Need examples of a pattern/API.
      - Want to know owners/maintainers.
      - Want to see similar implementations elsewhere.

  - **Sub-skills:**

    - **`/glean-code:codebase-context <system>`**  
      - **Use when:** You need high-level architecture or understanding of how a system fits together (e.g. “prep_publisher architecture”, “KDP ingestion pipeline”).  
      - **Goal:** Get an overview of components, data flows, and relevant repos/files.

    - **`/glean-code:find-examples <API/pattern>`**  
      - **Use when:** You’re unsure how to use an internal API or apply a pattern and want real usage examples across the org.  
      - **Examples:**  
        - `/glean-code:find-examples SegmentWriter`  
        - `/glean-code:find-examples "retry with backoff decorator"`  

    - **`/glean-code:code-owners <component>`**  
      - **Use when:** You need to know who maintains a component or who to loop in on a change/PR.  
      - **Examples:**  
        - `/glean-code:code-owners prep_publisher`  
        - `/glean-code:code-owners "events ingest service"`  

    - **`/glean-code:similar-code <pattern>`**  
      - **Use when:** You want to find similar implementations to model your change on, or to avoid re‑inventing a solution.  
      - **Examples:**  
        - `/glean-code:similar-code "idempotent consumer with exactly-once semantics"`  
        - `/glean-code:similar-code "kafka dlq handling"`  

---

You have access to these local repos and corresponding shell aliases:

1. **eng-handbook** (`handbook`)
    
    - **Purpose:** Central guide to how we build, ship, and operate software at Klaviyo, plus a directory to more detailed docs.
    - **How to use:**
        - When you need **best practices** or reference docs (e.g. Kubernetes, KDP, appfiles, deployment patterns), search and read files here first.
        - Useful example: `kubernetes/new_platform/appfiles.md` for how Appfiles work and how services are deployed to KDP.
    - **Navigation alias:** Run `handbook` to `cd` into the local `eng-handbook` repo.

2. **infrastructure-deployment** (`infra`)
    
    - **Purpose:** The **Deploy** repo, containing all infrastructure-as-code (Terraform, appfiles, ArgoCD config, etc.).
    - **How to use:**
        - Look here for **Terraform modules**, **Kubernetes cluster config**, and **Appfiles** (e.g. `apps/<team>/<service>/app.yaml`).
        - When changing deployments, you’ll often:
            - Edit an appfile under `apps/…`
            - Or modify Terraform in `infrastructure/...`
    - **Navigation alias:** Run `infra` to `cd` into the local `infrastructure-deployment` repo.

3. **k-repo** (`krepo`)
    
    - **Purpose:** The **Klaviyo backend monorepo**, housing backend services, shared libraries, and tooling. This is the approved home for all new backend services and libraries.
    - **How to use:**
        - Find service code, shared libs, and **BUILD** files for KDP (Klaviyo Developer Platform) / Kubernetes deployments.
        - Use Pants for builds and tests.
    - **Navigation alias:** Run `krepo` to `cd` into the local `k-repo` repo.
    - **Testing examples (Python)** for `prep_publisher`:
        - Full test file:
            
            ```bash
            LOG_LEVEL=info pants test python/klaviyo/data_exchange/prep_publisher/tests/server/test_main.py
            ```
            
        - Single test:
            
            ```bash
            pants test python/klaviyo/data_exchange/prep_publisher/tests/client/test_main.py -- -k test_failed_events_fallback_service_failed
            ```

4. **app** (`app`)
    
    - **Purpose:** The main **monolith** powering a large portion of Klaviyo’s core server-side functionality and APIs (e.g. event processing, core business logic).
    - **How to use:**
        - Use for work touching the legacy/monolithic system, ASG-based deployments, and app-in-KDP integrations.
    - **Navigation alias:** (If configured) use `app` to `cd` into the local `app` repo.  
        Note: if my shell alias is actually different, infer it from the current directory / path; don’t assume `app` works.
    - **Testing commands:**
        1. First set up Docker auth:
            
            ```bash
            klaviyocli docker setup
            ```
            
        2. Run multiple test files:
            
            ```bash
            make TEST="tests/services/events/ingest/service/test_base.py \
                       tests/appsec/users/test_users.py \
                       tests/partner_apps/orchestrator/test_orchestrator.py" docker-unit
            ```
            
        3. Run a single test:
            
            ```bash
            make TEST="tests/services/events/ingest/service/test_base.py::Class::test_foo" docker-unit
            ```

---

### How I want you to work

- **Prefer local context:**
    
    - Before suggesting code or commands, inspect the relevant local files, tests, and BUILD/appfile/Terraform definitions.
    - When I ask questions like “how is X deployed?” or “where is Y configured?”, search:
        - `eng-handbook` for docs and patterns.
        - `infrastructure-deployment` for appfiles and Terraform.
        - `k-repo` and/or `app` for implementation details and tests.

- **Be explicit about commands:**
    
    - When suggesting changes, include:
        - The **file path**.
        - The exact **diff** or code block to insert.
        - The **commands** to:
            - Format/lint (e.g. `pants fmt`, `pants lint`, `make lint`, etc. if you can infer from the repo).
            - Run tests (use the patterns above when relevant).
    - Prefer using the existing Pants/Make targets over ad-hoc python commands.

- **Deployment & KDP awareness:**
    
    - For services deployed via **KDP**:
        - Treat **k-repo** as the source of the image & CI.
        - Treat **infrastructure-deployment** appfiles as the source of truth for deployment config.
        - Use eng-handbook’s Kubernetes/new_platform docs (onboarding, appfiles, operations) as the reference for best practices.
    - Call out when a change will require:
        - An appfile update.
        - A Terraform update.
        - A coordinated rollout (e.g. dev → staging → prod).

- **Style of assistance:**
    
    - Default to **concrete, step-by-step** plans:
        - Where to edit.
        - What to change.
        - How to test locally.
        - How this will flow into CI/CD / appfile updates.
    - When something is ambiguous, state your **assumption** clearly and proceed (don’t ask me to decide unless absolutely necessary).

---

### When you’re unsure

If repo layout or tooling differs from your expectations, first:

1. Inspect the repo’s `README.md`, `docs/`, or `eng-handbook` references.
2. Show me what you found and propose a best-guess approach, with clear notes about any uncertainty.

Use all of the above as persistent working instructions whenever you’re helping me with this workspace.

---

If you’d like, I can next:  
- tighten this into a shorter “Claude skill” version, or  
- add a small “example prompts” section at the end to show how you expect to invoke these tools in practice.