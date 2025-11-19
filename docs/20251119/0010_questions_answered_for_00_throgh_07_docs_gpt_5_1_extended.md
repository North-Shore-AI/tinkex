1. StopReason Wire Format

---

**Answer:**

The API uses exactly **two** stop reasons, serialized as lowercase strings:

* `"length"`
* `"stop"`

These are the only allowed values.

**Code Evidence:**

```python
# File: tinker/types/stop_reason.py

__all__ = ["StopReason"]

StopReason: TypeAlias = Literal["length", "stop"]
```

And where it's used on the wire:

```python
# File: tinker/types/sampled_sequence.py

__all__ = ["SampledSequence"]

class SampledSequence(BaseModel):
    stop_reason: StopReason
    """Reason why sampling stopped"""

    tokens: List[int]
    """List of generated token IDs"""

    logprobs: Optional[List[float]] = None
    """Log probabilities for each token (optional)"""
```

**File Location:**

* `tinker/types/stop_reason.py`
* `tinker/types/sampled_sequence.py`

**Confidence:** High – the enum is a `Literal[...]` type alias, used directly in the response model.

2. RequestErrorCategory Casing

---

**Answer:**

`RequestErrorCategory` is a `StrEnum` whose values are the **lowercase** strings:

* `"unknown"`
* `"server"`
* `"user"`

Because it uses the standard-library `enum.StrEnum` with `auto()`, each member's *value* is the lowercase member name. Pydantic serializes enums using their `.value`, so JSON responses use lowercase strings. There is **no custom StrEnum** in this repo that changes the casing.

**Code Evidence:**

Definition:

```python
# File: tinker/types/request_error_category.py

__all__ = ["RequestErrorCategory"]

class RequestErrorCategory(StrEnum):
    Unknown = auto()
    Server = auto()
    User = auto()
```

Usage when parsing error responses from the futures API:

```python
# File: tinker/lib/api_future_impl.py  (inside _APIFuture._result_async)

result_dict: Any = await response.json()
error_category = RequestErrorCategory.Unknown

# If the server sent a category field, parse it via enum value:
error_category = RequestErrorCategory(result_dict.get("category"))

user_error = error_category is RequestErrorCategory.User
error_message = result_dict["error"]
```

And the response type that surfaces this to users:

```python
# File: tinker/types/request_failed_response.py

__all__ = ["RequestFailedResponse"]

class RequestFailedResponse(BaseModel):
    error: str
    category: RequestErrorCategory
```

**Why this implies lowercase JSON:**

* `RequestErrorCategory` inherits from `enum.StrEnum` and uses `auto()`.

* In Python 3.11+, `StrEnum` with `auto()` produces lowercase values:

  ```python
  from enum import StrEnum, auto

  class Foo(StrEnum):
      Unknown = auto()

  Foo.Unknown.value  # "unknown"
  ```

* Pydantic serializes an Enum to its `.value`. Therefore, JSON will have:

  ```json
  { "category": "unknown" }
  ```

**No custom StrEnum / lowercase patch:**

* In the provided code, `StrEnum` is only ever seen as a base class for `RequestErrorCategory`.
* There is **no** `tinker._types.StrEnum` or any custom `StrEnum` implementation/patch in the repo.
* No custom JSON encoders are defined for `RequestErrorCategory`.

**File Location:**

* `tinker/types/request_error_category.py`
* `tinker/lib/api_future_impl.py`
* `tinker/types/request_failed_response.py`

**Confidence:** High – behavior follows standard-library `StrEnum` and default Pydantic enum serialization, with direct enum construction from the JSON field.

3. JSON `null` Handling for Optional Fields

---

**Answer (short version):**

* The SDK **does not** have any global `exclude_none` configuration.
* The machinery only strips a custom sentinel `NotGiven`, **not** `None`.
* That means **optional fields that are `None` are serialized as `field: null`**, not omitted.
* Optional request fields like `SampleRequest.base_model: Optional[str] = None` will therefore appear as `"base_model": null` in the JSON body, unless there's some call-site passing `exclude_none=True` (which I do not see in the provided code).

**Code Evidence:**

Request/response base models:

```python
# File: tinker/_models.py

__all__ = ["StrictBase", "BaseModel", "GenericModel"]

class StrictBase(pydantic.BaseModel):
    """
    Don't allow extra fields, so user errors are caught earlier.
    Use this for request types.
    """
    model_config = ConfigDict(frozen=True, extra="forbid")


class BaseModel(pydantic.BaseModel):
    """
    Use for classes that may appear in responses. Allow extra fields, so old clients can still work.
    """

    # For future-proofing, we ignore extra fields in case the server adds new fields.
    model_config = ConfigDict(frozen=True, extra="ignore")
```

Notice: no `exclude_none` or similar in either config.

Typical request model with `Optional[...] = None`:

```python
# File: tinker/types/sample_request.py

__all__ = ["SampleRequest"]

class SampleRequest(StrictBase):
    num_samples: int = 1
    """Number of samples to generate"""

    prompt: ModelInput
    sampling_params: SamplingParams

    base_model: Optional[str] = None
    """Optional base model name to sample from."""

    model_path: Optional[str] = None
    """Optional tinker:// path to your model weights or LoRA weights."""

    sampling_session_id: Optional[str] = None
    """Optional sampling session ID to use instead of model_path/base_model."""

    seq_id: Optional[int] = None
    """Sequence ID within the sampling session."""

    prompt_logprobs: Optional[bool] = None
    """If set to `true`, computes and returns logprobs on the prompt tokens."""

    topk_prompt_logprobs: int = 0
    """If set to a positive integer, returns the top-k logprobs for each prompt token."""

    type: Literal["sample"] = "sample"

    # allow fields with a `model_` prefix
    model_config = ConfigDict(protected_namespaces=tuple())
```

The only place where fields are *removed* from outgoing request payloads is for the **custom sentinel** `NotGiven`, not for `None`:

```python
# File: tinker/_utils/_utils.py

@overload
def strip_not_given(obj: None) -> None: ...
@overload
def strip_not_given(obj: Mapping[_K, _V | NotGiven]) -> dict[_K, _V]: ...
@overload
def strip_not_given(obj: object) -> object: ...

def strip_not_given(obj: object | None) -> object:
    """Remove all top-level keys where their values are instances of `NotGiven`"""
    ...
```

This is wired into the HTTP request options:

```python
# File: tinker/_models.py  (FinalRequestOptions.construct, abbreviated)

class FinalRequestOptions(pydantic.BaseModel):
    ...
    json_data: Union[Body, None] = None
    extra_json: Union[AnyMapping, None] = None
    ...

    def construct(  # type: ignore
        ...
    ):
        kwargs: dict[str, Any] = {
            "method": method,
            "url": url,
            "params": strip_not_given(params),
            "headers": strip_not_given(headers),
            "json_data": strip_not_given(json_data),
            "extra_json": strip_not_given(extra_json),
            ...
        }
        # we unconditionally call `strip_not_given` on any value
        # as it will just ignore any non-mapping types
        return cast(FinalRequestOptions, super().construct(_fields_set, **kwargs))
```

And the transformer explicitly talks about `NotGiven`, not `None`:

```python
# File: tinker/_utils/_transform.py  (abbreviated)

result: dict[str, object] = {}
annotations = get_type_hints(expected_type, include_extras=True)

# we don't need to include `NotGiven` values here as they'll
# be stripped out before the request is sent anyway
...
```

There is **no** similar logic for `None`.

**Implications:**

* Request models don't use `NotGiven` for their fields; they use `Optional[...] = None`.
* The only thing that gets stripped is `NotGiven`, not `None`.
* There is no `exclude_none=True` in model configs or obvious serialization paths in this packed code.

So a `SampleRequest()` built with all defaults is expected to serialize with e.g. `"base_model": null` rather than omitting `base_model`.

**File Location:**

* `tinker/_models.py`
* `tinker/_utils/_utils.py`
* `tinker/_utils/_transform.py`
* `tinker/types/sample_request.py`

**Confidence:** Medium – the code clearly strips only `NotGiven`, not `None`, and there's no config for `exclude_none`, but the exact pydantic `.dict()`/`.model_dump()` call arguments are partially elided in the packed file, so I can't see a literal `exclude_none=False` or similar. Everything visible points strongly to `null` being sent for `None` fields.

4. Rate Limit Scope / Backoff State Sharing

---

**Answer (based on the provided code):**

* In this codebase, I **do not see any `_sample_backoff_until` attribute** on `InternalClientHolder` (or anywhere else).
* The retry/backoff logic is implemented with **local state per call** (and via `RetryHandler` for higher-level operations), not via a shared `_sample_backoff_until` field.
* That means there isn't a global "shared backoff timestamp" per `{base_url, api_key}` holder the way your docs suggest. Instead:

  * Network-level retries in `InternalClientHolder.execute_with_retries` use local `start_time`, `attempt_count`, and a computed `time_to_wait` with exponential backoff.
  * Higher-level retry logic is provided by `RetryHandler`, whose state is per-`RetryHandler` instance (and thus scoped to whatever client constructs it), not a global singleton.

So I **cannot confirm** that there is any shared per-holder `_sample_backoff_until` in v0.4.1; the mechanism seems to be per-call/per-handler, not a shared holder-level backoff field.

**Code Evidence:**

InternalClientHolder's retry logic:

```python
# File: tinker/lib/internal_client_holder.py  (abbreviated at bottom of file)

@staticmethod
def _is_retryable_status_code(status_code: int) -> bool
    ...

@staticmethod
def _is_retryable_exception(exception: Exception) -> bool
    ...

RETRYABLE_EXCEPTIONS = (
    ...
)

MAX_WAIT_TIME = 60 * 5
start_time = time.time()
attempt_count = 0

...

is_retryable = self._is_retryable_exception(e)
user_error = is_user_error(e)
current_time = time.time()
elapsed_time = current_time - start_time

# Apply exponential backoff
time_to_wait = min(2**attempt_count, 30)

# Don't wait too long if we're almost at the max wait time
time_to_wait = min(time_to_wait, start_time + MAX_WAIT_TIME - current_time)
```

This pattern indicates:

* `start_time`, `attempt_count`, `time_to_wait` are **local variables inside the retry loop**, not stored as attributes on `self`.
* There's no persisted `_sample_backoff_until` field here; each call's retry loop computes its own backoff schedule.

Higher-level generic retry handler used by public interfaces:

```python
# File: tinker/lib/retry_handler.py  (abbreviated)

@dataclass
class RetryConfig:
    max_connections: int = DEFAULT_CONNECTION_LIMITS.max_connections or 100
    progress_timeout: float = 30 * 60
    retry_delay_base: float = INITIAL_RETRY_DELAY
    retry_delay_max: float = MAX_RETRY_DELAY
    jitter_factor: float = 0.25
    enable_retry_logic: bool = True
    retryable_exceptions: tuple[Type[Exception], ...] = (
        ...
    )

class RetryHandler(Generic[T]):
    """
    A generalizable retry handler for API requests.
    ...
    """

    def __init__(self, config: RetryConfig = RetryConfig()):
        ...
        self._exception_counts = {}  # Track exception types and their counts
        ...
        self._last_global_progress = time.time()
        self._last_printed_progress = time.time()
        self._waiting_at_semaphore_count = 0
        self._in_retry_loop_count = 0

    async def execute(self, func: Callable[..., Awaitable[T]], *args: Any, **kwargs: Any) -> T:
        """Use as a direct function call."""
        ...

    async def _execute_with_retry(self, func: Callable[..., Awaitable[T]], *args: Any, **kwargs: Any) -> T:
        """Main retry logic."""
        start_time = time.time()
        attempt_count = 0
        ...
        should_retry = self._should_retry(e)
        ...
        retry_delay = self._calculate_retry_delay(attempt_count - 1)
        ...
```

State like `_last_global_progress` is per `RetryHandler` instance; it's not shared across all holders or globally.

SamplingClient hooks into this style of config (abridged):

```python
# File: tinker/lib/public_interfaces/sampling_client.py  (abridged)

U = TypeVar("U")

class SamplingClient(TelemetryProvider, QueueStateObserver):
    ...
    # Create retry handler with the provided configuration
    retry_config = retry_config or RetryConfig()
    ...
    untyped_future = await self.holder.execute_with_retries(
        ...
    )
    # Handle backoff
    ...
```

Given the packed view:

* I see retry logic, but no `_sample_backoff_until` attribute at all.
* Backoff for individual operations is determined within those retry loops and per-instance handlers.

**File Location:**

* `tinker/lib/internal_client_holder.py`
* `tinker/lib/retry_handler.py`
* `tinker/lib/public_interfaces/sampling_client.py`

**Confidence:** Low–Medium – I can see that there is **no `_sample_backoff_until` field in the provided code** and that backoff is implemented with local state and per-instance handlers, but because the file is packed/abridged, I can't absolutely rule out a tiny attribute definition in a truncated section. What I *can* say is that there is no obvious shared holder-level backoff flag being referenced in the visible retry logic.

5. `x-should-retry` Header

---

**Answer:**

Yes. The SDK **explicitly checks and honors** an `x-should-retry` response header in its core HTTP client. If the server sends this header, its value overrides the default retry heuristics.

**Code Evidence:**

From the core client's retry decision logic:

```python
# File: tinker/_base_client.py  (inside BaseClient._should_retry)

def _should_retry(self, response: httpx.Response) -> bool:
    # Note: this is not a standard header
    should_retry_header = response.headers.get("x-should-retry")

    # If the server explicitly says whether or not to retry, obey.
    if should_retry_header is not None:
        if should_retry_header.lower() == "true":
            return True
        if should_retry_header.lower() == "false":
            return False

    # Retry on request timeouts.
    # Retry on lock timeouts.
    # Retry on rate limits.
    # Retry internal errors.
    ...
```

This `_should_retry` method is consulted in the main request loop when an `httpx.HTTPStatusError` is raised:

```python
# Still in tinker/_base_client.py, in AsyncAPIClient.request(...) loop (abridged)

except httpx.HTTPStatusError as err:  # thrown on 4xx and 5xx status code
    response = err.response
    ...
    timeout = self._calculate_retry_timeout(
        response_headers=response.headers,
        remaining_retries=remaining_retries,
        ...
    )

    # Only retry if we both want to retry and have retries left
    if not self._should_retry(response) or remaining_retries <= 0 or timeout is None:
        raise
    ...
```

So:

* If `x-should-retry: false` is set, the SDK **will not** retry even if status code is normally retryable.
* If `x-should-retry: true` is set, it **will** retry even if the status code normally wouldn't.

**File Location:**

* `tinker/_base_client.py`

**Confidence:** High – the header is directly referenced and used to short-circuit retry behavior.

6. ImageChunk / ImageAssetPointerChunk Field Names

---

**Answer:**

* **ImageChunk** fields (JSON wire keys):

  * `data` – base64 string in JSON (bytes internally)
  * `format` – `"png"` or `"jpeg"`
  * `height` – integer pixels
  * `tokens` – integer (number of tokens this image represents)
  * `width` – integer pixels
  * `type` – literal `"image"`

* **ImageAssetPointerChunk** fields (JSON wire keys):

  * `format` – `"png"` or `"jpeg"`
  * `height` – integer pixels
  * `location` – string path or URL to image asset
  * `tokens` – integer
  * `width` – integer pixels
  * `type` – literal `"image_asset_pointer"`

So: it's `data` (not `image_data`) and `location` (not `asset_id`).

**Code Evidence:**

```python
# File: tinker/types/image_chunk.py

__all__ = ["ImageChunk"]

class ImageChunk(StrictBase):
    data: bytes
    """Image data as bytes"""

    format: Literal["png", "jpeg"]
    """Image format"""

    height: int
    """Image height in pixels"""

    tokens: int
    """Number of tokens this image represents"""

    width: int
    """Image width in pixels"""

    type: Literal["image"] = "image"

    @field_validator("data", mode="before")
    @classmethod
    def validate_data(cls, value: Union[bytes, str]) -> bytes:
        """Deserialize base64 string to bytes if needed."""
        ...

    @field_serializer("data")
    def serialize_data(self, value: bytes) -> str:
        """Serialize bytes to base64 string for JSON."""
        ...

    @property
    def length(self) -> int:
        ...
```

```python
# File: tinker/types/image_asset_pointer_chunk.py

__all__ = ["ImageAssetPointerChunk"]

class ImageAssetPointerChunk(StrictBase):
    format: Literal["png", "jpeg"]
    """Image format"""

    height: int
    """Image height in pixels"""

    location: str
    """Path or URL to the image asset"""

    tokens: int
    """Number of tokens this image represents"""

    width: int
    """Image width in pixels"""

    type: Literal["image_asset_pointer"] = "image_asset_pointer"

    @property
    def length(self) -> int:
        ...
```

**File Location:**

* `tinker/types/image_chunk.py`
* `tinker/types/image_asset_pointer_chunk.py`

**Confidence:** High – the full field lists and docstrings are present.
