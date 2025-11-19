1\. StopReason Wire Format



---



\*\*Answer:\*\*

The API uses exactly \*\*two\*\* stop reasons, serialized as lowercase strings:



\* `"length"`

\* `"stop"`



These are the only allowed values.



\*\*Code Evidence:\*\*



```python

\# File: tinker/types/stop\_reason.py



\_\_all\_\_ = \["StopReason"]



StopReason: TypeAlias = Literal\["length", "stop"]

```



And where it’s used on the wire:



```python

\# File: tinker/types/sampled\_sequence.py



\_\_all\_\_ = \["SampledSequence"]



class SampledSequence(BaseModel):

&nbsp;   stop\_reason: StopReason

&nbsp;   """Reason why sampling stopped"""



&nbsp;   tokens: List\[int]

&nbsp;   """List of generated token IDs"""



&nbsp;   logprobs: Optional\[List\[float]] = None

&nbsp;   """Log probabilities for each token (optional)"""

```



\*\*File Location:\*\*



\* `tinker/types/stop\_reason.py`

\* `tinker/types/sampled\_sequence.py`



\*\*Confidence:\*\* High – the enum is a `Literal\[...]` type alias, used directly in the response model.



2\. RequestErrorCategory Casing



---



\*\*Answer:\*\*

`RequestErrorCategory` is a `StrEnum` whose values are the \*\*lowercase\*\* strings:



\* `"unknown"`

\* `"server"`

\* `"user"`



Because it uses the standard-library `enum.StrEnum` with `auto()`, each member’s \*value\* is the lowercase member name. Pydantic serializes enums using their `.value`, so JSON responses use lowercase strings. There is \*\*no custom StrEnum\*\* in this repo that changes the casing.



\*\*Code Evidence:\*\*



Definition:



```python

\# File: tinker/types/request\_error\_category.py



\_\_all\_\_ = \["RequestErrorCategory"]



class RequestErrorCategory(StrEnum):

&nbsp;   Unknown = auto()

&nbsp;   Server = auto()

&nbsp;   User = auto()

```



Usage when parsing error responses from the futures API:



```python

\# File: tinker/lib/api\_future\_impl.py  (inside \_APIFuture.\_result\_async)



result\_dict: Any = await response.json()

error\_category = RequestErrorCategory.Unknown



\# If the server sent a category field, parse it via enum value:

error\_category = RequestErrorCategory(result\_dict.get("category"))



user\_error = error\_category is RequestErrorCategory.User

error\_message = result\_dict\["error"]

```



And the response type that surfaces this to users:



```python

\# File: tinker/types/request\_failed\_response.py



\_\_all\_\_ = \["RequestFailedResponse"]



class RequestFailedResponse(BaseModel):

&nbsp;   error: str

&nbsp;   category: RequestErrorCategory

```



\*\*Why this implies lowercase JSON:\*\*



\* `RequestErrorCategory` inherits from `enum.StrEnum` and uses `auto()`.



\* In Python 3.11+, `StrEnum` with `auto()` produces lowercase values:



&nbsp; ```python

&nbsp; from enum import StrEnum, auto



&nbsp; class Foo(StrEnum):

&nbsp;     Unknown = auto()



&nbsp; Foo.Unknown.value  # "unknown"

&nbsp; ```



\* Pydantic serializes an Enum to its `.value`. Therefore, JSON will have:



&nbsp; ```json

&nbsp; { "category": "unknown" }

&nbsp; ```



\*\*No custom StrEnum / lowercase patch:\*\*



\* In the provided code, `StrEnum` is only ever seen as a base class for `RequestErrorCategory`.

\* There is \*\*no\*\* `tinker.\_types.StrEnum` or any custom `StrEnum` implementation/patch in the repo.

\* No custom JSON encoders are defined for `RequestErrorCategory`.



\*\*File Location:\*\*



\* `tinker/types/request\_error\_category.py`

\* `tinker/lib/api\_future\_impl.py`

\* `tinker/types/request\_failed\_response.py`



\*\*Confidence:\*\* High – behavior follows standard-library `StrEnum` and default Pydantic enum serialization, with direct enum construction from the JSON field.



3\. JSON `null` Handling for Optional Fields



---



\*\*Answer (short version):\*\*



\* The SDK \*\*does not\*\* have any global `exclude\_none` configuration.

\* The machinery only strips a custom sentinel `NotGiven`, \*\*not\*\* `None`.

\* That means \*\*optional fields that are `None` are serialized as `field: null`\*\*, not omitted.

\* Optional request fields like `SampleRequest.base\_model: Optional\[str] = None` will therefore appear as `"base\_model": null` in the JSON body, unless there’s some call-site passing `exclude\_none=True` (which I do not see in the provided code).



\*\*Code Evidence:\*\*



Request/response base models:



```python

\# File: tinker/\_models.py



\_\_all\_\_ = \["StrictBase", "BaseModel", "GenericModel"]



class StrictBase(pydantic.BaseModel):

&nbsp;   """

&nbsp;   Don't allow extra fields, so user errors are caught earlier.

&nbsp;   Use this for request types.

&nbsp;   """

&nbsp;   model\_config = ConfigDict(frozen=True, extra="forbid")





class BaseModel(pydantic.BaseModel):

&nbsp;   """

&nbsp;   Use for classes that may appear in responses. Allow extra fields, so old clients can still work.

&nbsp;   """



&nbsp;   # For future-proofing, we ignore extra fields in case the server adds new fields.

&nbsp;   model\_config = ConfigDict(frozen=True, extra="ignore")

```



Notice: no `exclude\_none` or similar in either config.



Typical request model with `Optional\[...] = None`:



```python

\# File: tinker/types/sample\_request.py



\_\_all\_\_ = \["SampleRequest"]



class SampleRequest(StrictBase):

&nbsp;   num\_samples: int = 1

&nbsp;   """Number of samples to generate"""



&nbsp;   prompt: ModelInput

&nbsp;   sampling\_params: SamplingParams



&nbsp;   base\_model: Optional\[str] = None

&nbsp;   """Optional base model name to sample from."""



&nbsp;   model\_path: Optional\[str] = None

&nbsp;   """Optional tinker:// path to your model weights or LoRA weights."""



&nbsp;   sampling\_session\_id: Optional\[str] = None

&nbsp;   """Optional sampling session ID to use instead of model\_path/base\_model."""



&nbsp;   seq\_id: Optional\[int] = None

&nbsp;   """Sequence ID within the sampling session."""



&nbsp;   prompt\_logprobs: Optional\[bool] = None

&nbsp;   """If set to `true`, computes and returns logprobs on the prompt tokens."""



&nbsp;   topk\_prompt\_logprobs: int = 0

&nbsp;   """If set to a positive integer, returns the top-k logprobs for each prompt token."""



&nbsp;   type: Literal\["sample"] = "sample"



&nbsp;   # allow fields with a `model\_` prefix

&nbsp;   model\_config = ConfigDict(protected\_namespaces=tuple())

```



The only place where fields are \*removed\* from outgoing request payloads is for the \*\*custom sentinel\*\* `NotGiven`, not for `None`:



```python

\# File: tinker/\_utils/\_utils.py



@overload

def strip\_not\_given(obj: None) -> None: ...

@overload

def strip\_not\_given(obj: Mapping\[\_K, \_V | NotGiven]) -> dict\[\_K, \_V]: ...

@overload

def strip\_not\_given(obj: object) -> object: ...



def strip\_not\_given(obj: object | None) -> object:

&nbsp;   """Remove all top-level keys where their values are instances of `NotGiven`"""

&nbsp;   ...

```



This is wired into the HTTP request options:



```python

\# File: tinker/\_models.py  (FinalRequestOptions.construct, abbreviated)



class FinalRequestOptions(pydantic.BaseModel):

&nbsp;   ...

&nbsp;   json\_data: Union\[Body, None] = None

&nbsp;   extra\_json: Union\[AnyMapping, None] = None

&nbsp;   ...



&nbsp;   def construct(  # type: ignore

&nbsp;       ...

&nbsp;   ):

&nbsp;       kwargs: dict\[str, Any] = {

&nbsp;           "method": method,

&nbsp;           "url": url,

&nbsp;           "params": strip\_not\_given(params),

&nbsp;           "headers": strip\_not\_given(headers),

&nbsp;           "json\_data": strip\_not\_given(json\_data),

&nbsp;           "extra\_json": strip\_not\_given(extra\_json),

&nbsp;           ...

&nbsp;       }

&nbsp;       # we unconditionally call `strip\_not\_given` on any value

&nbsp;       # as it will just ignore any non-mapping types

&nbsp;       return cast(FinalRequestOptions, super().construct(\_fields\_set, \*\*kwargs))

```



And the transformer explicitly talks about `NotGiven`, not `None`:



```python

\# File: tinker/\_utils/\_transform.py  (abbreviated)



result: dict\[str, object] = {}

annotations = get\_type\_hints(expected\_type, include\_extras=True)



\# we don't need to include `NotGiven` values here as they'll

\# be stripped out before the request is sent anyway

...

```



There is \*\*no\*\* similar logic for `None`.



\*\*Implications:\*\*



\* Request models don’t use `NotGiven` for their fields; they use `Optional\[...] = None`.

\* The only thing that gets stripped is `NotGiven`, not `None`.

\* There is no `exclude\_none=True` in model configs or obvious serialization paths in this packed code.



So a `SampleRequest()` built with all defaults is expected to serialize with e.g. `"base\_model": null` rather than omitting `base\_model`.



\*\*File Location:\*\*



\* `tinker/\_models.py`

\* `tinker/\_utils/\_utils.py`

\* `tinker/\_utils/\_transform.py`

\* `tinker/types/sample\_request.py`



\*\*Confidence:\*\* Medium – the code clearly strips only `NotGiven`, not `None`, and there’s no config for `exclude\_none`, but the exact pydantic `.dict()`/`.model\_dump()` call arguments are partially elided in the packed file, so I can’t see a literal `exclude\_none=False` or similar. Everything visible points strongly to `null` being sent for `None` fields.



4\. Rate Limit Scope / Backoff State Sharing



---



\*\*Answer (based on the provided code):\*\*



\* In this codebase, I \*\*do not see any `\_sample\_backoff\_until` attribute\*\* on `InternalClientHolder` (or anywhere else).

\* The retry/backoff logic is implemented with \*\*local state per call\*\* (and via `RetryHandler` for higher-level operations), not via a shared `\_sample\_backoff\_until` field.

\* That means there isn’t a global “shared backoff timestamp” per `{base\_url, api\_key}` holder the way your docs suggest. Instead:



&nbsp; \* Network-level retries in `InternalClientHolder.execute\_with\_retries` use local `start\_time`, `attempt\_count`, and a computed `time\_to\_wait` with exponential backoff.

&nbsp; \* Higher-level retry logic is provided by `RetryHandler`, whose state is per-`RetryHandler` instance (and thus scoped to whatever client constructs it), not a global singleton.



So I \*\*cannot confirm\*\* that there is any shared per-holder `\_sample\_backoff\_until` in v0.4.1; the mechanism seems to be per-call/per-handler, not a shared holder-level backoff field.



\*\*Code Evidence:\*\*



InternalClientHolder’s retry logic:



```python

\# File: tinker/lib/internal\_client\_holder.py  (abbreviated at bottom of file)



@staticmethod

def \_is\_retryable\_status\_code(status\_code: int) -> bool

&nbsp;   ...



@staticmethod

def \_is\_retryable\_exception(exception: Exception) -> bool

&nbsp;   ...



RETRYABLE\_EXCEPTIONS = (

&nbsp;   ...

)



MAX\_WAIT\_TIME = 60 \* 5

start\_time = time.time()

attempt\_count = 0



...



is\_retryable = self.\_is\_retryable\_exception(e)

user\_error = is\_user\_error(e)

current\_time = time.time()

elapsed\_time = current\_time - start\_time



\# Apply exponential backoff

time\_to\_wait = min(2\*\*attempt\_count, 30)



\# Don't wait too long if we're almost at the max wait time

time\_to\_wait = min(time\_to\_wait, start\_time + MAX\_WAIT\_TIME - current\_time)

```



This pattern indicates:



\* `start\_time`, `attempt\_count`, `time\_to\_wait` are \*\*local variables inside the retry loop\*\*, not stored as attributes on `self`.

\* There’s no persisted `\_sample\_backoff\_until` field here; each call’s retry loop computes its own backoff schedule.



Higher-level generic retry handler used by public interfaces:



```python

\# File: tinker/lib/retry\_handler.py  (abbreviated)



@dataclass

class RetryConfig:

&nbsp;   max\_connections: int = DEFAULT\_CONNECTION\_LIMITS.max\_connections or 100

&nbsp;   progress\_timeout: float = 30 \* 60

&nbsp;   retry\_delay\_base: float = INITIAL\_RETRY\_DELAY

&nbsp;   retry\_delay\_max: float = MAX\_RETRY\_DELAY

&nbsp;   jitter\_factor: float = 0.25

&nbsp;   enable\_retry\_logic: bool = True

&nbsp;   retryable\_exceptions: tuple\[Type\[Exception], ...] = (

&nbsp;       ...

&nbsp;   )



class RetryHandler(Generic\[T]):

&nbsp;   """

&nbsp;   A generalizable retry handler for API requests.

&nbsp;   ...

&nbsp;   """



&nbsp;   def \_\_init\_\_(self, config: RetryConfig = RetryConfig()):

&nbsp;       ...

&nbsp;       self.\_exception\_counts = {}  # Track exception types and their counts

&nbsp;       ...

&nbsp;       self.\_last\_global\_progress = time.time()

&nbsp;       self.\_last\_printed\_progress = time.time()

&nbsp;       self.\_waiting\_at\_semaphore\_count = 0

&nbsp;       self.\_in\_retry\_loop\_count = 0



&nbsp;   async def execute(self, func: Callable\[..., Awaitable\[T]], \*args: Any, \*\*kwargs: Any) -> T:

&nbsp;       """Use as a direct function call."""

&nbsp;       ...



&nbsp;   async def \_execute\_with\_retry(self, func: Callable\[..., Awaitable\[T]], \*args: Any, \*\*kwargs: Any) -> T:

&nbsp;       """Main retry logic."""

&nbsp;       start\_time = time.time()

&nbsp;       attempt\_count = 0

&nbsp;       ...

&nbsp;       should\_retry = self.\_should\_retry(e)

&nbsp;       ...

&nbsp;       retry\_delay = self.\_calculate\_retry\_delay(attempt\_count - 1)

&nbsp;       ...

```



State like `\_last\_global\_progress` is per `RetryHandler` instance; it’s not shared across all holders or globally.



SamplingClient hooks into this style of config (abridged):



```python

\# File: tinker/lib/public\_interfaces/sampling\_client.py  (abridged)



U = TypeVar("U")



class SamplingClient(TelemetryProvider, QueueStateObserver):

&nbsp;   ...

&nbsp;   # Create retry handler with the provided configuration

&nbsp;   retry\_config = retry\_config or RetryConfig()

&nbsp;   ...

&nbsp;   untyped\_future = await self.holder.execute\_with\_retries(

&nbsp;       ...

&nbsp;   )

&nbsp;   # Handle backoff

&nbsp;   ...

```



Given the packed view:



\* I see retry logic, but no `\_sample\_backoff\_until` attribute at all.

\* Backoff for individual operations is determined within those retry loops and per-instance handlers.



\*\*File Location:\*\*



\* `tinker/lib/internal\_client\_holder.py`

\* `tinker/lib/retry\_handler.py`

\* `tinker/lib/public\_interfaces/sampling\_client.py`



\*\*Confidence:\*\* Low–Medium – I can see that there is \*\*no `\_sample\_backoff\_until` field in the provided code\*\* and that backoff is implemented with local state and per-instance handlers, but because the file is packed/abridged, I can’t absolutely rule out a tiny attribute definition in a truncated section. What I \*can\* say is that there is no obvious shared holder-level backoff flag being referenced in the visible retry logic.



5\. `x-should-retry` Header



---



\*\*Answer:\*\*

Yes. The SDK \*\*explicitly checks and honors\*\* an `x-should-retry` response header in its core HTTP client. If the server sends this header, its value overrides the default retry heuristics.



\*\*Code Evidence:\*\*



From the core client’s retry decision logic:



```python

\# File: tinker/\_base\_client.py  (inside BaseClient.\_should\_retry)



def \_should\_retry(self, response: httpx.Response) -> bool:

&nbsp;   # Note: this is not a standard header

&nbsp;   should\_retry\_header = response.headers.get("x-should-retry")



&nbsp;   # If the server explicitly says whether or not to retry, obey.

&nbsp;   if should\_retry\_header is not None:

&nbsp;       if should\_retry\_header.lower() == "true":

&nbsp;           return True

&nbsp;       if should\_retry\_header.lower() == "false":

&nbsp;           return False



&nbsp;   # Retry on request timeouts.

&nbsp;   # Retry on lock timeouts.

&nbsp;   # Retry on rate limits.

&nbsp;   # Retry internal errors.

&nbsp;   ...

```



This `\_should\_retry` method is consulted in the main request loop when an `httpx.HTTPStatusError` is raised:



```python

\# Still in tinker/\_base\_client.py, in AsyncAPIClient.request(...) loop (abridged)



except httpx.HTTPStatusError as err:  # thrown on 4xx and 5xx status code

&nbsp;   response = err.response

&nbsp;   ...

&nbsp;   timeout = self.\_calculate\_retry\_timeout(

&nbsp;       response\_headers=response.headers,

&nbsp;       remaining\_retries=remaining\_retries,

&nbsp;       ...

&nbsp;   )



&nbsp;   # Only retry if we both want to retry and have retries left

&nbsp;   if not self.\_should\_retry(response) or remaining\_retries <= 0 or timeout is None:

&nbsp;       raise

&nbsp;   ...

```



So:



\* If `x-should-retry: false` is set, the SDK \*\*will not\*\* retry even if status code is normally retryable.

\* If `x-should-retry: true` is set, it \*\*will\*\* retry even if the status code normally wouldn’t.



\*\*File Location:\*\*



\* `tinker/\_base\_client.py`



\*\*Confidence:\*\* High – the header is directly referenced and used to short-circuit retry behavior.



6\. ImageChunk / ImageAssetPointerChunk Field Names



---



\*\*Answer:\*\*



\* \*\*ImageChunk\*\* fields (JSON wire keys):



&nbsp; \* `data` – base64 string in JSON (bytes internally)

&nbsp; \* `format` – `"png"` or `"jpeg"`

&nbsp; \* `height` – integer pixels

&nbsp; \* `tokens` – integer (number of tokens this image represents)

&nbsp; \* `width` – integer pixels

&nbsp; \* `type` – literal `"image"`



\* \*\*ImageAssetPointerChunk\*\* fields (JSON wire keys):



&nbsp; \* `format` – `"png"` or `"jpeg"`

&nbsp; \* `height` – integer pixels

&nbsp; \* `location` – string path or URL to image asset

&nbsp; \* `tokens` – integer

&nbsp; \* `width` – integer pixels

&nbsp; \* `type` – literal `"image\_asset\_pointer"`



So: it’s `data` (not `image\_data`) and `location` (not `asset\_id`).



\*\*Code Evidence:\*\*



```python

\# File: tinker/types/image\_chunk.py



\_\_all\_\_ = \["ImageChunk"]



class ImageChunk(StrictBase):

&nbsp;   data: bytes

&nbsp;   """Image data as bytes"""



&nbsp;   format: Literal\["png", "jpeg"]

&nbsp;   """Image format"""



&nbsp;   height: int

&nbsp;   """Image height in pixels"""



&nbsp;   tokens: int

&nbsp;   """Number of tokens this image represents"""



&nbsp;   width: int

&nbsp;   """Image width in pixels"""



&nbsp;   type: Literal\["image"] = "image"



&nbsp;   @field\_validator("data", mode="before")

&nbsp;   @classmethod

&nbsp;   def validate\_data(cls, value: Union\[bytes, str]) -> bytes:

&nbsp;       """Deserialize base64 string to bytes if needed."""

&nbsp;       ...



&nbsp;   @field\_serializer("data")

&nbsp;   def serialize\_data(self, value: bytes) -> str:

&nbsp;       """Serialize bytes to base64 string for JSON."""

&nbsp;       ...



&nbsp;   @property

&nbsp;   def length(self) -> int:

&nbsp;       ...

```



```python

\# File: tinker/types/image\_asset\_pointer\_chunk.py



\_\_all\_\_ = \["ImageAssetPointerChunk"]



class ImageAssetPointerChunk(StrictBase):

&nbsp;   format: Literal\["png", "jpeg"]

&nbsp;   """Image format"""



&nbsp;   height: int

&nbsp;   """Image height in pixels"""



&nbsp;   location: str

&nbsp;   """Path or URL to the image asset"""



&nbsp;   tokens: int

&nbsp;   """Number of tokens this image represents"""



&nbsp;   width: int

&nbsp;   """Image width in pixels"""



&nbsp;   type: Literal\["image\_asset\_pointer"] = "image\_asset\_pointer"



&nbsp;   @property

&nbsp;   def length(self) -> int:

&nbsp;       ...

```



\*\*File Location:\*\*



\* `tinker/types/image\_chunk.py`

\* `tinker/types/image\_asset\_pointer\_chunk.py`



\*\*Confidence:\*\* High – the full field lists and docstrings are present.



