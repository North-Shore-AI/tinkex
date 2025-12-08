# Correctness-Sensitive Areas (Scientific Outcomes)

Where precision in the SDKs materially affects experimental or scientific results, and what to watch for across Elixir/Python parity work.

## Sampling (generation)
- **Rate limiting & backoff semantics:** Mis-enforced byte budgets or throttling changes the distribution of sampled outputs over time (e.g., more concurrent requests → more 429s → delayed or missing samples), biasing aggregate evaluations or A/Bs.
- **Queue state/ reason propagation:** Losing server-supplied pause reasons hides when the backend is capacity-limited vs rate-limited, leading to mis-attribution of latency or dropouts in eval pipelines.
- **Retry behavior on network/timeout:** Over-aggressive retries can duplicate requests; under-aggressive retries drop data. Both distort throughput and completeness of evaluation sets.

## Training loop
- **Batching/chunking heuristics (1024 items / 5 MB):** Over- or under-estimating size changes gradient statistics (batch composition), affecting convergence and reproducibility. Divergent chunking between SDKs yields different training trajectories on the same data.
- **Loss input sizing:** Incorrect byte/tensor size accounting can batch too much (OOM/timeout) or too little (under-utilization), altering learning rate schedules and wall-clock comparability.
- **Queue-state handling during training:** Ignoring pause signals can push work into backend throttling; overreacting reduces effective throughput, both affecting learning curves.

## Optimizer configuration
- **AdamParams fields (weight_decay, grad_clip_norm, eps, betas):** Defaults and validation must match; mismatches change optimization dynamics, especially for fine-tuning and small datasets. Silent clipping/decay differences can produce different model quality.
- **Numeric stability:** Epsilon and clipping differences can cause divergence or NaN explosions, especially on long runs or sharp-loss tasks.

## Error modeling & retries
- **Status/category mapping:** Misclassified 4xx/5xx errors change retry vs fail-fast behavior, leading to data loss (skipped steps) or duplication (replayed steps). This affects experiment integrity and checkpoint lineage.
- **TryAgainResponse handling:** Sleep durations and queue_state reasoning impact scheduling fairness and wall-clock time; inconsistent handling skews throughput metrics.

## Telemetry, logging, and observability
- **Structured telemetry parity:** Missing fields (queue_state_reason, request ids) hinder diagnosis of perf regressions and hide systemic biases (e.g., persistent capacity pauses).
- **Redaction & masking:** Incorrect handling risks leaking secrets into experiment artifacts/logs, which is a compliance and reproducibility hazard.

## Determinism and randomness
- **Seeding and RNG parity:** For stochastic components (sampling, shuffling, augmentation), differences in seed handling or RNG streams break reproducibility and cross-SDK comparison.
- **Floating-point differences:** Framework-level differences (Nx vs PyTorch/NumPy defaults) can subtly shift results; tolerance-aware assertions and golden runs are needed for cross-platform validation.

## Serialization and protocol fidelity
- **Schema alignment:** Field name/case mismatches (e.g., queue_state_reason) lead to ignored signals and degraded control flow.
- **Binary/text payload sizing:** Different encodings or length heuristics impact dispatch limits and batching, affecting both throughput and model updates.
