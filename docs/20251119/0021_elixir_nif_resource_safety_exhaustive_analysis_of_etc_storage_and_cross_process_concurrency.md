# **Elixir NIF Resource Safety: Exhaustive Analysis of ETS Storage and Cross-Process Concurrency**

## **Executive Summary**

The integration of high-performance native libraries into the Erlang virtual machine (BEAM) via Native Implemented Functions (NIFs) creates a complex intersection of memory models, concurrency guarantees, and lifecycle management strategies. The specific architectural pattern under review—instantiating a Rust-based tokenizers resource in one process, storing it in an Erlang Term Storage (ETS) table, and accessing it concurrently from arbitrary processes—represents a fundamental test of the BEAM's foreign function interface capabilities.

Based on a rigorous analysis of the Erlang Runtime System (ERTS) internals, the Rustler interoperability library, and the thread-safety characteristics of the Hugging Face tokenizers crate, the proposed implementation pattern is classified as **SAFE**. This verdict is contingent upon strict adherence to immutability principles on the native side and the correct configuration of the NIF scheduling strategy.

The resilience of NIF resources is structurally decoupled from the lifecycle of the creating process. NIF resources in the Erlang VM are reference-counted objects managed by the VM's internal allocators, not by process-specific heaps.1 When a resource is stored in an ETS table, the table acts as a persistent root for garbage collection, explicitly incrementing the reference count and preventing deallocation even if the originating process terminates.2 Furthermore, the tokenizers library in Rust is designed to be thread-safe (implementing the Sync trait), allowing the underlying data structure to be accessed concurrently by multiple BEAM schedulers without inducing data races or segmentation faults, provided the Rustler implementation correctly leverages ResourceArc.4

However, this safety is not without nuance. While the pattern is memory-safe, it introduces significant complexities regarding CPU scheduling and "dirty" operations. NIF execution blocks the calling scheduler thread. If the encode function consumes excessive reductions without yielding, it must be scheduled as a Dirty NIF to prevent scheduler collapse.6 Additionally, historical bugs in optimizing modules like persistent_term regarding magic references warrant a cautious approach to alternative storage mechanisms.7

This report provides an exhaustive deconstruction of the mechanisms at play, detailing the lifecycle of NIF resources, the interaction between ETS and native pointers, and the specific safety guarantees provided by Rustler. It concludes with architectural recommendations designed to ensure production stability.

---

## **1. The Theoretical Framework of NIFs on the BEAM**

To determine the safety of storing NIF resources in ETS, one must first establish a foundational understanding of how the BEAM manages the memory of native objects. Unlike standard Erlang terms (lists, tuples, small integers) which are typically copied between process heaps, or large binaries which are stored on a shared heap, NIF resources are opaque handles pointing to memory allocated outside the managed heap of the calling process. This distinction is critical for understanding cross-process safety.

### **1.1. The Anatomy of a "Magic Reference"**

The Erlang NIF API introduces the concept of a "resource object" to safely manage pointers to native data structures. In the context of the BEAM, these are often referred to as "magic references." A magic reference is a term that looks and behaves like a reference-counted binary from the perspective of the Erlang garbage collector, but instead of pointing to raw binary data, it points to a custom C or Rust struct.1

When a NIF allocates a resource using enif_alloc_resource, the VM allocates a block of memory that is managed via atomic reference counting. This memory is not allocated in the process heap; it is allocated in the system heap or via the allocator defined by the NIF library.1 The lifecycle of this object is deterministic but entirely dependent on reference proliferation.

#### **The Allocation Sequence**

1. **Creation:** When the native code calls enif_alloc_resource, a memory block is created with an initial reference count of 1. This creates the native object but does not yet expose it to the Erlang VM as a term.
2. **Term Generation:** To pass this resource back to the calling Erlang process, the native code calls enif_make_resource. This function constructs the "magic reference" term. Crucially, this operation increments the reference count of the underlying resource.1 The term returned to the process is essentially a handle that keeps the resource alive.
3. **Releasing Ownership:** Typically, the native C/Rust code calls enif_release_resource immediately after creating the Erlang term. This decrements the count by 1. At this stage, the resource remains alive solely because the Erlang term (the magic reference) held by the calling process maintains a count of 1.1

This memory management model implies that the resource is fundamentally **not owned** by the process that created it. It is owned by the reference count itself. As long as *any* valid reference to the resource exists—whether in a process heap, an ETS table, a persistent term, or even a message in transit—the resource remains allocated.2

### **1.2. Decoupling from Process Lifecycle**

The user's primary concern regarding safety is whether the tokenizer resource remains valid after the creating process dies. The evidence confirms that NIF resources obey strict garbage collection rules that prevent premature deallocation.

When a BEAM process terminates, either normally or abnormally, the VM performs a cleanup of that process's stack and heap. Any terms residing on that heap are garbage collected. For a standard term, the memory is reclaimed immediately. For a NIF resource or a reference-counted binary, "garbage collection" means the generic reference associated with that process is removed. This triggers an atomic decrement of the resource's reference count.9

However, if that resource was shared prior to the process death, the reference count logic ensures survival. If Process A creates a resource and then sends it to Process B, Process B receives a copy of the magic reference. This copy operation increments the atomic counter. If Process A subsequently dies, its reference is removed (decrement), but Process B's reference remains (count > 0), keeping the resource alive.

### **1.3. The Deterministic Destructor**

Every NIF resource type has an associated destructor function defined during the initialization of the resource type via enif_open_resource_type. The VM guarantees that this destructor is called only when the reference count drops exactly to zero.1

This destructor is the native equivalent of a finalizer. It allows the library to free memory, close file descriptors, release database connections, or unlock mutexes. Because the destructor is tied to the reference count and not the creating process ID, the resource is agnostic to the topology of the processes using it. It behaves as a truly shared, reference-counted object.

---

## **2. The Role of ETS in Native Resource Management**

The interactions between Erlang Term Storage (ETS) and NIF resources are distinct from how ETS handles standard Erlang terms. This distinction is pivotal for the safety of the proposed architecture.

### **2.1. Mechanics of Insertion and Reference Counting**

When a standard Erlang term (like a list or a tuple) is inserted into an ETS table, the data is typically deep-copied from the process heap into the ETS table's memory space. This ensures that if the process dies, the data in ETS remains valid because it is a completely independent copy.

For NIF resources, the behavior is optimized. When Process A inserts a tokenizer into ETS:

```elixir
:ets.insert(:tokenizers_cache, {"gpt2", tokenizer})
```

The BEAM recognizes the tokenizer term as a NIF resource (a magic reference). Instead of attempting to serialize or deep-copy the underlying Rust struct—which would be impossible for opaque native types—it copies the *reference*.

Crucially, the act of inserting the reference into ETS triggers an atomic increment of the resource's reference counter.2 The ETS table itself becomes a "owner" of a reference.

### **2.2. Survival Analysis: Creator Process Death**

Consider the scenario where Process A (the creator) terminates immediately after insertion.

1. **Before Termination:** Reference count is 2 (1 held by Process A, 1 held by ETS).
2. **Termination:** Process A's heap is garbage collected. The reference held by Process A is removed.
3. **Decrement:** The resource's reference count drops from 2 to 1.
4. **Survival:** Because the count is non-zero (held by ETS), the destructor is **not** triggered. The memory block containing the Rust Tokenizer struct remains allocated and valid.3

This mechanism confirms that caching NIF resources in ETS is a standard and safe pattern for prolonging the life of native objects beyond the lifespan of ephemeral worker processes. The resource will only be destructed if it is explicitly deleted from the table, or if the table itself is destroyed (which happens if the *table owner* process dies).12

### **2.3. Cross-Process Pointer Validity**

The user asks: "Can arbitrary processes safely call NIF functions on a resource created elsewhere?" This question essentially interrogates the validity of the native pointer across execution contexts.

In the Erlang VM, NIF resources are fundamentally **VM-global**. The pointer wrapped by the resource is a pointer to a virtual memory address in the host operating system's heap (allocated via enif_alloc or Rust's Box). This address space is shared by all threads within the OS process that hosts the BEAM.6

Unlike process-specific resources in some operating system constructs (like file descriptors in unshared contexts), a pointer in the BEAM's address space is universally accessible by all schedulers. If Process B retrieves the tokenizer handle from ETS, it obtains a valid pointer to the memory address.

However, possessing a valid pointer is only half the battle. The safety of *using* that pointer concurrently depends entirely on the thread-safety of the native code it points to.

---

## **3. Rustler: The Safety Bridge**

The safety of the user's implementation relies heavily on the guarantees provided by Rustler, the library bridging Elixir and Rust. Rustler is not merely a binding generator; it is a safety enforcement layer that leverages Rust's type system to prevent the very segmentation faults that plague C-based NIFs.

### **3.1. ResourceArc: The Thread-Safe Container**

Rustler wraps the raw Erlang NIF resource pointer in a type called ResourceArc<T>.14 This type mimics the behavior of Rust's standard std::sync::Arc (Atomic Reference Counted) smart pointer, but it delegates the actual reference counting logic to the Erlang VM's enif_keep_resource and enif_release_resource APIs.14

The ResourceArc serves as the container for the native struct (in this case, the Tokenizer). When a NIF function is called, Rustler decodes the incoming reference term into a ResourceArc<Tokenizer>.

### **3.2. The Send and Sync Trait Enforcement**

The most critical safety feature of Rustler regarding ETS usage is its trait bounds. Rustler enforces that any type T wrapped in a ResourceArc must implement both Send and Sync.4

* **Send:** A type is Send if it is safe to transfer ownership of it to another thread. Since NIF resources can be passed between processes (and thus between scheduler threads), they must be Send.
* **Sync:** A type is Sync if it is safe for multiple threads to access it concurrently via shared references (i.e., &T is Send).15

Because ETS allows multiple processes to read the same resource handle simultaneously, and those processes may be executing on different scheduler threads at the exact same moment, the underlying resource is effectively being accessed via shared references across threads.

If the Tokenizer struct in Rust did not implement Sync (e.g., if it used interior mutability via RefCell which is not thread-safe), Rustler would **refuse to compile** the NIF code.4 This compile-time guarantee is the strongest evidence for the safety of the architecture. It ensures that if the code builds, the underlying data structure is thread-safe.

### **3.3. Implicit Synchronization**

Since ResourceArc requires Sync, the user implementation relies on the tokenizers library to handle synchronization.

* **Concurrent Reads:** If the library exposes methods that take &self (immutable reference), concurrent calls are safe. Rust's borrow checker guarantees that no mutation occurs through &self, preventing data races.
* **Internal Mutability:** If the library needs to mutate state during an operation (e.g., updating a cache), it must use thread-safe interior mutability primitives like std::sync::Mutex or RwLock. If it does so, it remains Sync, and the locking is handled internally.

---

## **4. Deep Dive into the tokenizers Library**

To validate the safety of the specific library in question, we must examine the properties of the Hugging Face tokenizers Rust crate. Theoretical safety via Rustler is one thing; actual library behavior is another.

### **4.1. Thread Safety of Tokenizer**

The Hugging Face tokenizers library is explicitly designed for high-performance, parallelized tokenization.

* **Rust Implementation:** The core Tokenizer struct is composed of modular components (Model, Normalizer, PreTokenizer, PostProcessor). These components are generally stateless or immutable during the encoding phase. The library is widely used in Python environments (via the tokenizers Python package) where the "Fast" tokenizers release the Global Interpreter Lock (GIL) to allow multi-threaded tokenization.5
* **Maintainer Confirmation:** Discussions in the tokenizers GitHub repository explicitly confirm that the encode method is thread-safe. Maintainers have stated, "It should be yes, encode supports multi threading" and recommend letting the tokenizer handle threading rather than implementing external locks.5
* **Immutability:** The standard encode operation on a pre-trained tokenizer is semantically a read-only operation. It takes &self. While some tokenizers might conceptually have internal caches, the Rust compiler ensures that if these exist, they are wrapped in thread-safe containers if the type claims to be Sync.

### **4.2. Comparison with Python "Already Borrowed" Errors**

The research identified specific concurrency issues in Python usage, where users encountered "Already Borrowed" runtime errors.19 It is crucial to understand why these do not apply to Elixir.

* **The Python Context:** These errors arise from the PyO3 bindings. PyO3 enforces borrow checking rules at runtime. If a Python thread attempts to mutate the tokenizer (e.g., add_tokens) while another thread is encoding, PyO3 detects a violation of Rust's borrowing rules (multiple readers + one writer) and panics or throws an exception.
* **The Elixir Difference:** Elixir's usage pattern via Rustler relies on ResourceArc. The cached resource in ETS is essentially immutable. The Elixir API generally exposes encode (which takes &self) but separates configuration/training into a different lifecycle phase. As long as the Elixir implementation does not expose a mutable function (taking &mut self) to be called on the *same* resource instance that is stored in ETS, these runtime borrow errors are structurally impossible.

### **4.3. The Necessity of Dirty Schedulers**

While memory safety is assured, operational safety requires attention to execution time. Tokenization is a CPU-bound task. Running complex models (like BPE or Unigram) on long input strings can easily exceed the 1 millisecond time slice allotted to NIFs by the BEAM scheduler.6

* **Scheduler Collapse Risk:** If a NIF blocks a standard scheduler for too long, it can disrupt the VM's load balancing and timer firing, leading to what is known as "scheduler collapse".23
* **Mitigation:** The encode function must be tagged as a Dirty NIF.

  ```rust
  #[rustler::nif(schedule = "DirtyCpu")]
  fn encode(...)
  ```

  This offloads the execution to a separate thread pool dedicated to long-running CPU tasks, ensuring the main schedulers remain responsive.6

---

## **5. Concurrency & Scheduler Mechanics**

The interaction between ETS read_concurrency and NIF execution is a critical optimization point.

### **5.1. ETS Lock Contention**

ETS tables are protected by locks. By default, a set table has a single lock (or bucket-level locks). When multiple processes attempt to look up the tokenizer:

1. Process A acquires a read lock on the ETS bucket.
2. It copies the magic reference (pointer).
3. It increments the native reference count.
4. It releases the lock.

This operation is extremely fast. However, if thousands of processes do this simultaneously, lock contention on the ETS table can become a bottleneck.

**Optimization:** The ETS table must be created with the read_concurrency: true option. This creates a table optimized for concurrent read operations, usually by utilizing a decentralized locking scheme or atomic readers.25

### **5.2. Scheduler Parallelism**

Once the reference is retrieved, the actual execution of Tokenizer.encode happens in the calling process's scheduler (or dirty scheduler).

* **True Parallelism:** Because the NIF is thread-safe and the BEAM uses one scheduler per CPU core, multiple processes can execute the Rust encode function literally in parallel on different cores.
* **Scalability:** This architecture scales linearly with the number of CPU cores, limited only by the hardware and potentially by any internal locks within the Rust tokenizers library (though encode is generally lock-free for inference).

---

## **6. Alternative Architectures & Trade-offs**

To ensure the chosen pattern is optimal, we compare it against viable alternatives, incorporating specific findings regarding persistent_term risks.

### **Table 1: Architecture Comparison**

| Feature | Option A: Global ETS (Current) | Option B: persistent_term | Option C: GenServer Pool |
| :---- | :---- | :---- | :---- |
| **Read Speed** | Very Fast (O(1)) | **Extremely Fast** (Literal, no copy) | Slow (Message Passing overhead) |
| **Concurrency** | **High** (Parallel access) | **High** (Parallel access) | **Low** (Serialized access) |
| **Update Cost** | Low (Local lock) | **Prohibitive** (Global GC) | Low (State update) |
| **Memory Usage** | Low (Reference sharing) | Low (Reference sharing) | Higher (Process overhead) |
| **Safety Risks** | Low | **Moderate** (Historical bugs, GC stalls) | Very Low |
| **Best For** | Dynamic/Lazy loading models | Static configuration only | Non-thread-safe resources |

### **6.1. The Risks of persistent_term**

The persistent_term module offers faster lookups than ETS because it avoids copying terms to the process heap; it returns a reference to the term on a literal heap.3 For NIF resources, this distinction is subtle (since ETS only copies the pointer anyway), but persistent_term avoids the ETS locking overhead.

However, persistent_term has significant downsides:

1. **Global GC on Updates:** Updating or deleting a term triggers a global garbage collection scan of *every* process in the VM to ensure no references are dangling.2 If the application updates tokenizers dynamically (e.g., loading a new model on demand), this will cause severe latency spikes.
2. **Magic Reference Bugs:** Historical bugs (specifically OTP-17677 and OTP-17700) have been identified where persistent_term could prematurely deallocate magic references (NIF resources) under specific conditions involving message passing or multiple references.7 While patched in recent OTP versions (24+), this history suggests persistent_term interacts with magic references in complex ways that are less battle-tested than ETS.

### **6.2. The Bottleneck of GenServers**

Wrapping the tokenizer in a GenServer (where the GenServer "owns" the resource and handles call requests) provides serialization. This is only necessary if the underlying library is not thread-safe (e.g., legacy C libraries with global state).27

For a thread-safe Rust library, this introduces unnecessary serialization. If 100 processes want to tokenize text, they effectively form a queue, utilizing only a single core for tokenization regardless of available hardware.28

---

## **7. Failure Modes & Mitigation Strategies**

Despite the positive safety verdict, specific failure modes must be mitigated in a production environment.

### **7.1. Segmentation Faults via unsafe**

* **Risk:** Low.
* **Mechanism:** A segfault in a NIF crashes the entire BEAM. This bypasses all Erlang supervision trees.6
* **Mitigation:** The tokenizers crate is written in Rust, which guarantees memory safety for safe code. Rustler catches Rust panics (e.g., unwrap on None) and converts them to Erlang exceptions rather than crashing the VM.14 This makes Rust-based NIFs significantly safer than C-based ones. Developers should audit their own glue code to ensure no unsafe blocks are used improperly.

### **7.2. Memory Leaks via Reference Retention**

* **Risk:** Moderate.
* **Mechanism:** Because ETS holds a reference, the NIF resource is never freed until the table entry is deleted. If the application generates unique keys for tokenizers (e.g., creating a custom tokenizer per user session) and caches them without eviction, native memory usage will grow unbounded. The Erlang GC cannot see inside the ETS table to "clean up" unused entries.30
* **Mitigation:**
  1. **Bounded Cache:** Use a library like Cachex (which uses ETS) to enforce a maximum size or TTL (Time To Live) for cached tokenizers.
  2. **Monitoring:** Use enif_monitor_process within the NIF if resources need to be strictly tied to process lifecycles, though for a global cache, this is less relevant.6

### **7.3. Mutable State Contention**

* **Risk:** Low for encode, High for configuration.
* **Mechanism:** If the Rust implementation uses RwLock for internal state (like a cache), and a process attempts to write to it (e.g., add_tokens) while others are reading, contention occurs. If the implementation is incorrect (e.g. deadlocks in Rust), the NIF calls will hang, blocking the dirty schedulers.
* **Mitigation:** Treat cached tokenizers as strictly immutable. Perform all configuration (training, special token addition) in a setup phase *before* inserting the resource into ETS. Do not expose mutable methods in the Elixir API for the cached objects.

---

## **8. Conclusion and Recommendations**

The architectural pattern of caching tokenizers NIF resources in ETS tables is **SAFE** and highly recommended for production Elixir applications requiring high-performance NLP tasks. The combination of the BEAM's robust reference-counting memory model and Rustler's compile-time thread-safety enforcement provides a stable foundation for cross-process resource sharing.

### **8.1. Implementation Checklist**

To ensure the safety and stability of this implementation, the following checklist should be adhered to:

1. **Rustler Configuration:** Ensure the Tokenizer resource is wrapped in ResourceArc and the encode NIF is annotated with `#[rustler::nif(schedule = "DirtyCpu")]`.24
2. **ETS Optimization:** Initialize the ETS table with `[:set, :public, :named_table, read_concurrency: true]` to minimize lock contention during high-throughput access.26
3. **Immutability:** Expose only read-only operations (encoding, decoding) on the cached resource.
4. **Cache Management:** Implement an eviction strategy if the set of models is dynamic to prevent native memory leaks.

### **8.2. Recommended Code Structure**

The following Elixir module demonstrates the safe creation and caching of the resource, incorporating the recommended ETS settings.

```elixir
defmodule MyApp.TokenizerCache do
  use GenServer

  # The 'owner' process of this table must be stable (e.g., a Supervisor or long-lived GenServer).
  # If this process dies, the table and all tokenizer references are destroyed.
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(_) do
    # :public -> Any process can read/write
    # :read_concurrency -> Optimizes for multiple readers (critical for this use case)
    :ets.new(:tokenizers_cache, [:set, :public, :named_table, read_concurrency: true])
    {:ok, nil}
  end

  # Public API to get or load
  def get_or_load(model_name) do
    case :ets.lookup(:tokenizers_cache, model_name) do
      [{^model_name, tokenizer}] ->
        # 1. Fast path: Return the NIF resource directly.
        # The VM increments the ref count here. Safe to use in calling process.
        {:ok, tokenizer}

      [] ->
        # 2. Slow path: Load and cache.
        # Note: Race conditions here are benign (model loaded twice),
        # but can be mitigated with :ets.insert_new/2 or serialization if needed.
        load_and_cache(model_name)
    end
  end

  defp load_and_cache(model_name) do
    with {:ok, tokenizer} <- Tokenizers.Tokenizer.from_pretrained(model_name) do
      # Insert into ETS. Table now holds a reference.
      # Original 'tokenizer' variable in this process also holds a reference.
      :ets.insert(:tokenizers_cache, {model_name, tokenizer})
      {:ok, tokenizer}
    end
  end
end

# Usage in arbitrary worker process
defmodule MyApp.Worker do
  def process_text(text) do
    # Retrieves handle (Ref Count ++). Native memory is valid.
    {:ok, tokenizer} = MyApp.TokenizerCache.get_or_load("gpt2")

    # Calls NIF. Thread-safe Rust code executes on Dirty CPU scheduler.
    Tokenizers.Tokenizer.encode(tokenizer, text)
  end
end
```

### **8.3. Final Verdict**

The proposed architecture leverages the strengths of both the BEAM (fault-tolerant concurrency, reference-counted binaries) and Rust (thread-safety without data races). By avoiding the pitfalls of persistent_term updates and the bottlenecks of GenServer serialization, this pattern represents the optimal approach for integrating the tokenizers library into a scalable Elixir system.

#### **Works cited**

1. Properly free memory alloc'd with enif_resource_alloc - Stack Overflow, accessed November 19, 2025, [https://stackoverflow.com/questions/14554658/properly-free-memory-allocd-with-enif-resource-alloc](https://stackoverflow.com/questions/14554658/properly-free-memory-allocd-with-enif-resource-alloc)
2. Clever use of persistent_term - Erlang/OTP, accessed November 19, 2025, [https://www.erlang.org/blog/persistent_term/](https://www.erlang.org/blog/persistent_term/)
3. persistent_term — erts v16.1.1 - Erlang, accessed November 19, 2025, [https://www.erlang.org/doc/apps/erts/persistent_term.html](https://www.erlang.org/doc/apps/erts/persistent_term.html)
4. Resource in rustler - Rust - Docs.rs, accessed November 19, 2025, [https://docs.rs/rustler/latest/rustler/trait.Resource.html](https://docs.rs/rustler/latest/rustler/trait.Resource.html)
5. Issue #1726 · huggingface/tokenizers - Thread safe? - GitHub, accessed November 19, 2025, [https://github.com/huggingface/tokenizers/issues/1726](https://github.com/huggingface/tokenizers/issues/1726)
6. erl_nif — erts v16.1.1 - Erlang, accessed November 19, 2025, [https://www.erlang.org/doc/apps/erts/erl_nif.html](https://www.erlang.org/doc/apps/erts/erl_nif.html)
7. 1 ERTS Release Notes - Erlang/OTP, accessed November 19, 2025, [https://www.erlang.org/docs/23/apps/erts/notes](https://www.erlang.org/docs/23/apps/erts/notes)
8. [erlang-questions] Reference counting in NIFs, accessed November 19, 2025, [http://erlang.org/pipermail/erlang-questions/2013-August/075087.html](http://erlang.org/pipermail/erlang-questions/2013-August/075087.html)
9. [erlang-questions] question about NIF resources - Google Groups, accessed November 19, 2025, [https://groups.google.com/g/erlang-programming/c/rh_fpIKh3Fo](https://groups.google.com/g/erlang-programming/c/rh_fpIKh3Fo)
10. Memory management of processes - if I forget about a process will it get cleaned up or will it leak unless manually killed?, accessed November 19, 2025, [https://erlangforums.com/t/memory-management-of-processes-if-i-forget-about-a-process-will-it-get-cleaned-up-or-will-it-leak-unless-manually-killed/4320](https://erlangforums.com/t/memory-management-of-processes-if-i-forget-about-a-process-will-it-get-cleaned-up-or-will-it-leak-unless-manually-killed/4320)
11. The NIF resource is destroyed if you put it in the ETS table - #6 by garazdawi - Elixir Forum, accessed November 19, 2025, [https://elixirforum.com/t/the-nif-resource-is-destroyed-if-you-put-it-in-the-ets-table/18335/6](https://elixirforum.com/t/the-nif-resource-is-destroyed-if-you-put-it-in-the-ets-table/18335/6)
12. Erlang Term Storage (ETS) - Elixir School, accessed November 19, 2025, [https://elixirschool.com/en/lessons/storage/ets/](https://elixirschool.com/en/lessons/storage/ets/)
13. Using C from Elixir with NIFs - Andrea Leopardi, accessed November 19, 2025, [https://andrealeopardi.com/posts/using-c-from-elixir-with-nifs/](https://andrealeopardi.com/posts/using-c-from-elixir-with-nifs/)
14. "ResourceArc" Search - Rust - Docs.rs, accessed November 19, 2025, [https://docs.rs/rustler/latest/rustler/?search=ResourceArc](https://docs.rs/rustler/latest/rustler/?search=ResourceArc)
15. Send and Sync - The Rustonomicon, accessed November 19, 2025, [https://doc.rust-lang.org/nomicon/send-and-sync.html](https://doc.rust-lang.org/nomicon/send-and-sync.html)
16. Thread Safety (Send/Sync, Arc, Mutex) - Rust Training Slides by Ferrous Systems, accessed November 19, 2025, [https://rust-training.ferrous-systems.com/latest/book/thread-safety](https://rust-training.ferrous-systems.com/latest/book/thread-safety)
17. rust - Understanding the Send trait - Stack Overflow, accessed November 19, 2025, [https://stackoverflow.com/questions/59428096/understanding-the-send-trait](https://stackoverflow.com/questions/59428096/understanding-the-send-trait)
18. Fast Tokenizers: How Rust is Turbocharging NLP | by Mohammad Shojaei | Medium, accessed November 19, 2025, [https://medium.com/@mshojaei77/fast-tokenizers-how-rust-is-turbocharging-nlp-dd12a1d13fa9](https://medium.com/@mshojaei77/fast-tokenizers-how-rust-is-turbocharging-nlp-dd12a1d13fa9)
19. `HuggingFace error: Already borrowed` when running tokenizer in multi-threaded mode · Issue #1421 · stanford-crfm/helm - GitHub, accessed November 19, 2025, [https://github.com/stanford-crfm/helm/issues/1421](https://github.com/stanford-crfm/helm/issues/1421)
20. RuntimeError: Already borrowed · Issue #537 · huggingface/tokenizers - GitHub, accessed November 19, 2025, [https://github.com/huggingface/tokenizers/issues/537](https://github.com/huggingface/tokenizers/issues/537)
21. Experiencing https://github.com/huggingface/tokenizers/issues/537 issue when sentence-transformer is used for generating embeddings · Issue #794 · UKPLab/sentence-transformers, accessed November 19, 2025, [https://github.com/UKPLab/sentence-transformers/issues/794](https://github.com/UKPLab/sentence-transformers/issues/794)
22. Writing Rust NIFs for your Elixir code with the Rustler package | by Jacob Lerche | Medium, accessed November 19, 2025, [https://medium.com/@jacob.lerche/writing-rust-nifs-for-your-elixir-code-with-the-rustler-package-d884a7c0dbe3](https://medium.com/@jacob.lerche/writing-rust-nifs-for-your-elixir-code-with-the-rustler-package-d884a7c0dbe3)
23. NIFs are the fastest method to call external code from Erlang/Elixir, as far as ... | Hacker News, accessed November 19, 2025, [https://news.ycombinator.com/item?id=13610633](https://news.ycombinator.com/item?id=13610633)
24. Elixir and Rust is a good mix · The Phoenix Files - Fly.io, accessed November 19, 2025, [https://fly.io/phoenix-files/elixir-and-rust-is-a-good-mix/](https://fly.io/phoenix-files/elixir-and-rust-is-a-good-mix/)
25. Erlang Term Storage (ETS) - Elixir School, accessed November 19, 2025, [https://elixirschool.com/en/lessons/storage/ets](https://elixirschool.com/en/lessons/storage/ets)
26. Unlock Blazing Fast In-Memory Power: The Rails Developer's Guide to Mastering ETS in Elixir | by Jonny Eberhardt | Medium, accessed November 19, 2025, [https://medium.com/@jonnyeberhardt7/unlock-blazing-fast-in-memory-power-the-rails-developers-guide-to-mastering-ets-in-elixir-4872c3d50909](https://medium.com/@jonnyeberhardt7/unlock-blazing-fast-in-memory-power-the-rails-developers-guide-to-mastering-ets-in-elixir-4872c3d50909)
27. Using a non-thread safe library in a NIF - Questions / Help - Elixir Forum, accessed November 19, 2025, [https://elixirforum.com/t/using-a-non-thread-safe-library-in-a-nif/47987](https://elixirforum.com/t/using-a-non-thread-safe-library-in-a-nif/47987)
28. How we fixed a client library bottleneck with Elixir concurrency - Duffel, accessed November 19, 2025, [https://duffel.com/blog/client-library-bottleneck-elixir-concurrency](https://duffel.com/blog/client-library-bottleneck-elixir-concurrency)
29. rusterlium/rustler: Safe Rust bridge for creating Erlang NIF functions - GitHub, accessed November 19, 2025, [https://github.com/rusterlium/rustler](https://github.com/rusterlium/rustler)
30. Tracking Down an ETS-related Memory Leak | by Tyler Pachal - Medium, accessed November 19, 2025, [https://tylerpachal.medium.com/tracking-down-an-ets-related-memory-leak-a115a4499a2f](https://tylerpachal.medium.com/tracking-down-an-ets-related-memory-leak-a115a4499a2f)
