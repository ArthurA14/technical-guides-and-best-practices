# I) Operating principle of the component

## AsyncIO (FastAPI) vs Celery + Redis: the fundamental difference

This note explains **why "FastAPI + AsyncIO" is not the same thing as "FastAPI + Celery + Redis"**, even if a simple Hello World can look similar.

---

## 1) Main components (Celery architecture)

### API (Producer)
A normal FastAPI service that:
- receives HTTP requests (e.g., `POST /generate-report`)
- **creates a job** by publishing a message to a broker (Redis)
- returns quickly with a `task_id` (and optionally exposes `/tasks/{id}/status`)

> The **API**'s role is to **submit work**, **not to execute** heavy work.

### Broker (Redis)
Redis acts as a **message broker / queue**:
- **stores** job messages durably (at least for the lifetime of Redis)
- distributes jobs to workers
- enables buffering/backpressure (a queue can grow when load spikes, but the API does not collapse)

Optionally, Redis can also be the **result backend** (store job status/results), but in real systems you often store **large outputs** elsewhere (S3/MinIO, DB, Elasticsearch, etc.) and keep only pointers/metadata in Celery.

### Worker (Consumer)
A separate process/pod that:
- pulls jobs from Redis when it has capacity (concurrency)
- **executes** the task code
- updates the status/result backend

> The **worker** is the "**execution engine**" that runs outside your HTTP server.

---

## 2) The fundamental difference (where execution happens)

### With AsyncIO-only (FastAPI)
- The request arrives to the API.
- The API **executes the work itself** (in-process), either:
  - synchronously (blocking), or
  - asynchronously (`async def` / `await`) for I/O-bound work.
- Scaling means: **more API replicas**, and each replica is responsible for both:
  - handling HTTP traffic
  - **running the heavy jobs**

### With Celery + Redis
- The request arrives to the API.
- The API **only enqueues** the job into Redis and **returns quickly**.
- A worker later **picks** the job from the queue (when it can) and executes it.
- Scaling means: **you can scale the API and workers independently**.

**Key statement:**
> In the Celery model, the **API produces jobs**, the **broker stores them**, and the **worker executes them**.  
> The **API** is **no longer the execution bottleneck**.
> If a worker dies, another

---

## 3) When to use what (rule of thumb)

### Use AsyncIO (FastAPI-only) when:
- tasks are **short** (typically < 1 second, sometimes a few seconds max)
- workload is mostly **I/O-bound** (DB reads, s**hort HTTP calls**)
- you can **tolerate losing** in-flight work **if a pod restarts**
- you **don't need durable queueing**, retries, or offline processing.

### Use Celery + Redis when:
- tasks are **long** (multiple seconds to minutes)
- tasks are **CPU-heavy** (PDF generation, parsing, image processing, embedding, ML/LLM inference)
- tasks are **unpredictable** (variable runtimes, external services, rate limits)
- you need:
  - **durable buffering** (backpressure)
  - **retries/backoff**
  - **resource isolation**
  - **independent scaling** of "HTTP capacity" vs "compute capacity"

---

## 4) Why Celery is valuable (practical advantages)

### 4.1 Independent scaling (the big one win)
- **Scale the API** to absorb **traffic** (requests per second).
- **Scale workers** to absorb **compute** (jobs per minute).
- Different worker pools per queue:
  - `ingestion` workers vs `reportgen` workers
  - different CPU/RAM/GPU profiles and concurrency settings.

### 4.2 Resource isolation (API stays healthy)
**Heavy jobs no longer run inside your HTTP pods**.
- The API **stays responsive**.
- You avoid saturating the web server with long-running jobs.
- Failures in job execution do **not** directly **crash the API process**.


### 4.3 Parallelization (capacity multiplication, not duplication)

Celery follows a **competing consumers pattern**:
- 1 published job
- 1 worker executes it
- Multiple workers can process multiple jobs **in parallel**.

If you enqueue:
- `1 delay()` -> 1 job executed once
- `3 delay()` -> 3 jobs executed

If you run:
- `2 workers` -> **capacity is doubled**.
- this is **not** a **duplication**

Workers do **not** execute the **same job multiple times**.
They compete for available jobs and process them concurrently.

This enables:
- Parallel ingestion of multiple documents.
- Parallel report generation for multiple users.
- Horizontal scaling by simply increasing worker replicas.

### 4.4 Resilience (acknowledgment + requeue mechanism)

Reliability in Celery does **not** come from sending multiple copies of a job.

It comes from the **acknowledgment mechanism**:

- A job is published to the broker.
- A **single** worker picks it up and execute it.
- The job is acknowledged (**ack**) only after successful processing

If:
- a worker crashes
- a Kubernetes pod restarts
- a node dies

Then:
- The **not ack** job **returns to the queue**.
- **Another worker** can & will **pick it up**.

So the system provides **at-least-once delivery** with **automatic reprocessing of unfinished jobs**.

> Therefore, **reliability comes from the ack + requeue mechanism**.

Important:
- Logical execution remains **one job = one intended result**.
- It is not redundancy by duplication.
- Idempotence must be handled at the application level if needed.

### 4.5 Backpressure (queue absorbs spikes)
With a broker:
- You can accept a burst of requests (enqueue quickly).
- The **queue grows temporarily** and it does **not affect the compute task ever**.
- Workers drain the queue at a controlled rate.

Without a broker:
- The "**queue**" becomes your **HTTP layer**: open connections, timeouts, memory pressure.
- Under load, the system collapses in a much harsher way.

### 4.6 Avoid "self-DDoS" of the API
If your API **both** accepts **requests** and **runs expensive work**:
- A burst of requests can **consume a huge amount of CPU/RAM** very quick.
- The API stops responding in time.
- **clients retry** -> **load increases** -> **cascading failure**.

**Celery** prevents that by:
- **Keeping** the **API fast** (enqueue + return).
- **Moving compute** to **worker pools**.

---

## 5) Concrete scenario: scaling only the API vs scaling workers

Consider heavy tasks:
- LLM calls (variable latency, rate limits).
- heavy Elasticsearch indexing (batch transforms, embeddings).
- PDF or large JSON generation (tens of seconds).
- pipeline steps with external dependencies and occasional failures.

### Case A — AsyncIO + scale only the API (more replicas)
**What happens:**
1. **Each request** starts a **long job inside the API pod**.
2. Your API worker threads/processes get occupied.
3. API latency skyrockets: -> **requests timeout**.
4. The ingress load balancer **keeps sending more traffic**.
5. Clients retry: -> traffic multiplies.
6. CPU/RAM saturates: -> pods restart: -> in-flight work is lost.
7. You get a feedback loop: retries + restarts = system collapse.

**Even with `asyncio`:**
- `asyncio` helps when tasks are **mostly waiting on I/O**.
- But **LLM orchestration** +/or **PDF generation** +/or **heavy indexing** often includes **CPU-heavy** or **long blocking phases**.
- If you run those inside the API pod, your **HTTP capacity becomes your compute capacity**.

### Case B — Celery + Redis + scale workers (separate execution)
**What happens:**
1. API receives the request and enqueues a job (fast).
2. API returns `task_id` **immediately**: -> **user** can **poll** `/status` or receive callbacks.
3. The **queue buffers the burst** (controlled backlog).
4. **Workers** **consume jobs** as **capacity allows**:
   - **scale workers up if backlog grows** (manually or autoscaling).
   - **throttle concurrency per worker** to **protect downstream systems** (LLM/ES).
5. **API remains stable** because it is **not blocked** by long jobs.
6. Failures trigger retries/backoff **without taking down the web tier**.

**Net result:**
- The system degrades gracefully (**queue length grows**) instead of catastrophically (**timeouts and restarts**).
- You can tune and **scale** the **compute layer** **independently**.

---

## 6) Summary

- **AsyncIO** improves concurrency ***inside*** your API process, **mainly for I/O-bound** tasks.
- **Celery + Redis** provides a **distributed task queue**:
  - durable buffering
  - decoupled execution
  - independent scaling
  - resource isolation
  - safer handling of long/CPU-heavy jobs

If the job takes **tens of seconds**, touches **LLMs**, performs **heavy indexing**, or produces **large PDF/JSON**, Celery-style workers are usually the correct architecture. AsyncIO alone is not a substitute for a task queue; it's a **concurrency tool inside one service**.
