# Gap: ServiceClient.get_server_capabilities

## Python surface
- `ServiceClient.get_server_capabilities()` / `get_server_capabilities_async()` returns `types.GetServerCapabilitiesResponse`.

## Elixir state
- Low-level endpoint exists: `Tinkex.API.Service.get_server_capabilities/1` (`lib/tinkex/api/service.ex:11-22`).
- No `ServiceClient` wrapper or GenServer clause; callers cannot access capabilities via the high-level client.

## Impact
- Feature discovery, UI population, and client-side validation cannot use the Elixir SDK’s public entry point. Users must call low-level API modules directly, breaking parity expectations.

## Remediation sketch
1) Add `get_server_capabilities/1` and `get_server_capabilities_async/1` (returning `Task.t()`), delegating through the `Service` API with the client’s config and telemetry metadata.
2) Wire a `handle_call` clause to invoke the API and return `{:ok, %GetServerCapabilitiesResponse{}} | {:error, %Tinkex.Error{}}`.
3) Expose a thin helper on `Tinkex.ServiceClient` that issues the GenServer call.

## Testing ideas
- Unit: mock `Tinkex.API.Service` to return a fixture; assert `{:ok, %GetServerCapabilitiesResponse{}}` is propagated.
- Integration: start a ServiceClient with a test adapter and verify the call path honors telemetry metadata and pool selection (`:session`).
