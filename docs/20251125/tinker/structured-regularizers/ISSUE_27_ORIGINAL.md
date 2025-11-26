# Original Issue Text: tinker-feedback#27

**Issue URL:** https://github.com/thinking-machines-lab/tinker-feedback/issues/27
**Status:** Marked "Completed" by danobi on 2025-11-23 (but no code landed)
**Filed by:** nshkrdotcom

---

## Summary

Stabilize and document the existing custom loss functionality in TrainingClient as a first-class research extensibility feature, adding structured regularizer composition, async execution support for expensive computations, and improved telemetry to make domain-specific training objectives accessible to researchers without low-level training loop implementation.

## Current State and Motivation

Tinker currently provides custom loss capability through the `CustomLossFnV1` callback interface and `forward_backward_custom` methods in TrainingClient. This mechanism allows researchers to inject arbitrary loss terms by computing gradients client-side and passing them back to Tinker as weighted linear losses. The architecture correctly separates concerns: expensive domain-specific computation runs in the user's environment where specialized libraries are available, while Tinker infrastructure handles the actual backward pass and parameter updates.

However, this powerful capability exists primarily as an internal implementation detail rather than a documented, supported research feature. The current interface presents several practical barriers that limit its utility for the research workflows it was designed to enable.

First, discoverability remains poor. Researchers exploring Tinker's capabilities for projects requiring structured regularization have no clear path to this functionality without reading TrainingClient internals. The custom loss mechanism is not positioned in documentation as a core research extensibility point, leading researchers to conclude incorrectly that Tinker only supports standard objectives.

Second, the callback signature handles all custom loss computation as a single monolithic function. For research projects requiring multiple regularization terms with different conceptual purposes, this forces researchers to manually compose and weight components within their callback, then manually decompose metrics for logging. A narrative synthesis project might need topological consistency penalties, sparsity constraints, and fairness regularizers, each requiring separate hyperparameter tuning and ablation studies. The current interface provides no structure for expressing this composition cleanly.

Third, the synchronous callback execution model creates a performance bottleneck for computationally expensive regularizers. Computing Betti numbers via persistent homology, running SMT solvers for logical consistency checks, or querying external knowledge bases can take seconds per batch. When these computations execute synchronously within the event loop, they block all other training operations, dramatically reducing throughput. While the SDK includes asyncification utilities, they are not integrated into the custom loss pathway, leaving researchers to implement their own threading or process pool management.

Fourth, telemetry for custom losses lacks structure. Metrics returned from callbacks appear in logs, but the system provides no standardized way to track individual regularizer contributions, compare their relative magnitudes, or analyze how their weights affect training dynamics. This makes hyperparameter tuning and debugging significantly more difficult than necessary.

## Proposed Enhancements

### 1. Public API Stabilization and Documentation

Promote the custom loss callback system from internal mechanism to documented, supported public API. This involves establishing clear contracts for callback signatures, providing comprehensive examples demonstrating integration with domain-specific libraries like GUDHI for topological analysis or Z3 for logical verification, and explaining how the linearization process works so researchers understand the mathematical foundations. Documentation should include end-to-end examples showing how researchers working on specific problem domains would integrate their constraints into Tinker-managed training.

### 2. Structured Regularizer Composition

Extend the TrainingClient interface to support explicit regularizer composition rather than requiring monolithic callbacks. The proposed design would allow researchers to define multiple named regularizers with independent weights:

```python
def topological_consistency(outputs, batch_data):
    graphs = extract_reasoning_graphs(batch_data)
    betti_numbers = compute_persistent_homology(graphs)
    return torch.mean(betti_numbers), {"beta_1_mean": betti_numbers.mean().item()}

def sparsity_penalty(outputs, batch_data):
    activations = outputs["hidden_states"]
    return torch.norm(activations, p=1), {"l1_norm": activations.norm(p=1).item()}

training_config = {
    "base_loss": "cross_entropy",
    "regularizers": [
        {"fn": topological_consistency, "weight": 0.1, "name": "topology"},
        {"fn": sparsity_penalty, "weight": 0.01, "name": "sparsity"}
    ]
}
```

The training system would automatically compose these regularizers, apply weights, aggregate their outputs, and structure telemetry so that each component's contribution appears separately in metrics. This design enables clean ablation studies where researchers can enable or disable specific regularizers, tune their weights independently, and analyze their individual effects on training dynamics.

### 3. Async Execution Support

Provide native support for computationally expensive callbacks through an async-aware interface. The enhancement would offer two execution modes:

For callbacks that naturally support async operations, allow async function signatures that can await external services or I/O-bound computations without blocking the training event loop. For CPU-intensive synchronous computations that cannot be easily converted to async, provide an execution mode that automatically runs the callback in a thread pool, allowing the main training loop to proceed while expensive regularizers compute in parallel.

The implementation should handle the complexity of coordinating async callbacks with the forward-backward cycle, ensuring that gradient updates wait for all regularizer computations to complete while allowing other training operations to proceed. This would significantly improve throughput for workflows requiring expensive domain-specific computations.

### 4. Enhanced Telemetry and Debugging

Standardize how metrics from custom regularizers flow into Tinker's logging system. When researchers specify multiple regularizers, the system should automatically track individual contributions to the total loss, report the gradient magnitude from each component, and monitor how regularizer values change across training. This structured telemetry enables researchers to identify when specific constraints are dominating the training signal, detect when regularizer weights need adjustment, and understand the interaction between multiple objectives.

## Technical Considerations

These enhancements build directly on existing infrastructure without requiring fundamental architectural changes. The current linearization mechanism for passing custom gradients back to Tinker remains unchanged. The core insight that expensive computations should run client-side while Tinker handles the actual backward pass continues to hold. The proposed improvements primarily affect the interface ergonomics and execution model rather than the underlying mathematics or communication protocol.

Implementation should maintain backward compatibility with existing code using `CustomLossFnV1` and `forward_backward_custom`. The enhancements would be additive, providing a higher-level interface that researchers can adopt incrementally while the lower-level mechanisms remain available for advanced use cases requiring fine-grained control.

## Benefits to Research Community

Formalizing this capability addresses the gap between researchers who need sophisticated training objectives and platforms designed to make advanced training accessible. The current situation forces researchers to either abandon needed constraints or abandon managed platforms to implement custom training loops from scratch. This enhancement eliminates that forced choice.

Structured regularizer composition enables cleaner research workflows. Projects exploring multi-objective optimization, studying the interaction between different constraints, or conducting ablation studies across regularizer combinations all become significantly more tractable when the training system provides explicit composition support rather than requiring manual orchestration in monolithic callbacks.

Async support removes a major performance bottleneck. Research projects requiring external knowledge base queries, theorem prover integration, simulation-based validation, or other expensive per-batch computations become feasible within managed training infrastructure. This expands the range of research questions that Tinker can support without sacrificing the reliability and convenience that make managed platforms valuable.

Enhanced telemetry transforms the debugging and tuning experience. When the system automatically tracks individual regularizer contributions, researchers can quickly identify which constraints are affecting training, understand whether their weights need adjustment, and diagnose unexpected behavior. This visibility is essential for research requiring careful balancing of multiple objectives.

## Relationship to Original Vision

The existing custom loss mechanism demonstrates that Tinker was designed with research extensibility in mind. The architecture correctly separates managed infrastructure from domain-specific logic. However, the current implementation treats this capability as an advanced feature for users willing to read internal code rather than a core research affordance. This enhancement request argues for elevating and refining what already exists rather than building something fundamentally new.

By formalizing the custom loss system as a documented, ergonomic, performant research feature, Tinker would more fully realize its positioning as a platform for sophisticated research rather than only a fine-tuning service. The proposed improvements maintain Tinker's abstraction boundaries while making powerful capabilities accessible to researchers whose work requires going beyond standard objectives.

---

## Issue Status Notes

**2025-11-23:** Issue closed by danobi with state_reason: "completed"

**2025-11-25:** Upon inspection of recent commits (9bf0df6, 937c36e, 097e108, 951d660), no implementation of structured regularizers, async support, or enhanced telemetry was found. The "Sync contents" commits contain only:
- Documentation generation pipeline updates
- Docstring formatting changes
- Type export additions (WeightsInfoResponse, GetSamplerResponse)
- Test coverage for ServiceClient endpoints

The issue appears to have been closed without corresponding code changes landing in the repository.
