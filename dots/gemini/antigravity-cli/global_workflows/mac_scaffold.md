## Project Specification: Modular Automation Core (MAC)

### Goal
Design and implement a single, highly scalable, and resource-efficient automation core powered by local LLM inference via the ggml ecosystem (llama.cpp). This core will serve as a foundational engine capable of being rapidly specialized and deployed across multiple distinct automation tasks (e.g., structured data ingestion, notification dispatching, API orchestration, and multi-stream content routing).

### Target Application Domains
* **News & Data Aggregation:** Real-time stream parsing, entity extraction, and content classification.
* **Information Routing & Notification Systems:** Multi-channel alert handling, customer service ticketing triage, and automated reporting interfaces.
* **Financial Data Parsing:** Extraction of structured primitives from raw text feeds, log analysis, and system state verification.

### Core Architecture Principles
* **Functional Modularity:** Swappable, atomic components isolating system I/O from core processing logic.
* **Deterministic Resource Boundaries:** Absolute bounds on memory consumption, CPU utilization, and thread allocation to maintain host system stability under heavy parallel loads.
* **Schema-Driven Execution:** Reliance on strict context-free grammars to ensure machine-to-machine reliability without manual string parsing.

---

## Technical Requirements

### 1. Core Architecture & Component Layout
* **Decoupled Event Loop:** Asynchronous network and API handling (Go channels / goroutines) must run independently of the synchronous processing pipeline.
* **Local Tensor Execution Layer (ggml):** Direct local compilation via static links or native wrappers (go-llama.cpp). No external cloud API dependencies.
* **Automated Logic Routing:** Utilizes small, hyper-efficient open-weight models (e.g., Llama-3.2-3B or Gemma-2-2B at Q4_K_M precision) acting as central intent classifiers.
* **Data Serialization & Type Safety:** Enforced system outputs using GBNF (GGML Backus-Naur Form) grammars to guarantee that the local network outputs raw, valid JSON matching application structs natively.
* **State Isolation:** The core inference engine remains completely stateless. Session tracking, history management, and token context windows are managed via an external fast-access cache (e.g., Redis or an in-memory ring buffer) and injected per request.

### 2. High-Scale Resource Management
* **Memory Optimization:** Enforcement of virtual memory locking (mlock) to pin model weights permanently into physical RAM, preventing kernel disk-swapping latency spikes.
* **Bounded Concurrency Worker Pools:** Implement a strictly governed worker pool pattern to handle incoming data queues. The number of concurrent tensor processing jobs must be hard-capped relative to available CPU/GPU hardware threads.
* **Scratchpad Memory Management:** Utilize pre-allocated execution graphs within the tensor runtime to completely eliminate runtime dynamic allocation/deallocation overhead during generation cycles.

### 3. Monitoring, Diagnostics & Analytics
* **Structured JSON Logging:** Native implementation of zero-allocation structured logs (e.g., using rs/zerolog or uber-go/zap) tracking transaction latency, token-per-second generation speeds, and error states.
* **Health & Readiness Probes:** Exposed HTTP endpoints tracking current engine queue depth, execution latency, and internal memory usage metrics for container orchestrators.
* **Circuit Breaking:** Graceful degradation logic to handle backpressure when incoming event queues exceed maximum buffer depth.

---

## Deployment & Scaffolding Targets

* **Runtime Target:** Single compiled, zero-dependency static binary (Go with statically linked libllama.a).
* **Containerization:** Clean, multi-stage Dockerfile optimized to build the native Cgo/C++ bindings in a build environment before copying the minimal artifact and .gguf` model files into a hardened, lightweight scratch/alpine base layer.
