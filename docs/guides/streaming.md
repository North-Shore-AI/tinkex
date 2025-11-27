# Streaming

This guide covers Tinkex's streaming capabilities for working with Server-Sent Events (SSE) from event-stream endpoints.

## Overview

Tinkex provides low-level streaming support through the SSE (Server-Sent Events) decoder, which can parse incremental chunks of event data from HTTP streams. The primary use case is consuming real-time event streams from compatible endpoints.

The streaming implementation consists of two main components:

- `Tinkex.Streaming.SSEDecoder` - A stateful decoder that parses SSE-formatted data
- `Tinkex.API.StreamResponse` - A wrapper struct containing the enumerable stream and metadata

## Server-Sent Events Format

Server-Sent Events follow a simple text-based format where each event is separated by double newlines (`\n\n`, `\r\n\r\n`, or `\r\r`). Each event consists of one or more fields:

```
event: custom_event_name
data: {"key": "value"}
id: event-123
retry: 5000

```

**Field types:**
- `event` - Event type identifier (optional)
- `data` - Event payload, can span multiple lines
- `id` - Event ID for tracking (optional)
- `retry` - Reconnection delay in milliseconds (optional)
- Lines starting with `:` are comments and ignored

## Using the SSEDecoder

The `SSEDecoder` module provides a stateful decoder that can be fed incremental binary chunks. This is useful when processing streaming HTTP responses where data arrives in fragments.

### Basic usage

```elixir
alias Tinkex.Streaming.{SSEDecoder, ServerSentEvent}

# Create a new decoder
decoder = SSEDecoder.new()

# Feed binary chunks as they arrive
chunk1 = "data: {\"message\": \"hello\"}\n\n"
{events1, decoder} = SSEDecoder.feed(decoder, chunk1)

# First event is parsed
[%ServerSentEvent{data: data}] = events1
IO.inspect(data)  # "{\"message\": \"hello\"}"

# Continue feeding more chunks
chunk2 = "event: update\ndata: {\"count\": 42}\n\n"
{events2, decoder} = SSEDecoder.feed(decoder, chunk2)
```

### The ServerSentEvent struct

Each parsed event is represented as a `ServerSentEvent` struct:

```elixir
%ServerSentEvent{
  event: "custom",           # Event type (or nil for unnamed events)
  data: "{\"value\": 123}",  # Event payload as string
  id: "evt-001",             # Event ID (or nil)
  retry: 5000                # Retry delay in ms (or nil)
}
```

### Decoding JSON data

Use `ServerSentEvent.json/1` to attempt JSON decoding of the event data:

```elixir
event = %ServerSentEvent{data: "{\"result\": 42}"}

decoded = ServerSentEvent.json(event)
# Returns: %{"result" => 42}

# If JSON parsing fails, returns the raw string
event = %ServerSentEvent{data: "plain text"}
ServerSentEvent.json(event)
# Returns: "plain text"
```

## Handling Partial Chunks

The decoder maintains an internal buffer to handle partial events that span multiple chunks:

```elixir
decoder = SSEDecoder.new()

# First chunk contains incomplete event
{[], decoder} = SSEDecoder.feed(decoder, "data: {\"par")

# Second chunk completes the event
{events, decoder} = SSEDecoder.feed(decoder, "tial\"}\n\n")

[event] = events
event.data  # "{\"partial\"}"
```

The decoder automatically:
- Buffers incomplete events
- Handles various line ending styles (`\n`, `\r\n`, `\r`)
- Supports double-newline separators in all formats
- Processes multiple events in a single chunk

## Streaming with the API Client

The `Tinkex.API` module provides `stream_get/2` for consuming SSE endpoints directly:

```elixir
{:ok, stream_response} = Tinkex.API.stream_get("/api/v1/events", config: config)

# Access stream metadata
stream_response.status       # 200
stream_response.method       # :get
stream_response.url          # Full URL
stream_response.headers      # Response headers map

# Process events from the stream
stream_response.stream
|> Enum.each(fn event ->
  IO.inspect(event, label: "Received event")
end)
```

### Custom event parsing

By default, `stream_get/2` parses event data as JSON. You can customize this with the `:event_parser` option:

```elixir
# Return raw ServerSentEvent structs
{:ok, response} =
  Tinkex.API.stream_get("/events",
    config: config,
    event_parser: :raw
  )

response.stream
|> Enum.each(fn %ServerSentEvent{} = event ->
  IO.puts("Event type: #{event.event}")
  IO.puts("Data: #{event.data}")
end)

# Use custom parser function
parser = fn event ->
  # Custom transformation logic
  event.data
  |> String.upcase()
end

{:ok, response} =
  Tinkex.API.stream_get("/events",
    config: config,
    event_parser: parser
  )
```

### Example: Processing a stream

```elixir
alias Tinkex.API

# Configure the client
config = Tinkex.Config.new(
  api_key: System.fetch_env!("TINKER_API_KEY"),
  timeout: 30_000  # Longer timeout for streaming
)

# Connect to an event stream
{:ok, stream_resp} = API.stream_get("/api/v1/notifications", config: config)

# Process events as they arrive
stream_resp.stream
|> Stream.filter(fn event ->
  event["type"] == "notification"
end)
|> Stream.map(fn event ->
  %{
    timestamp: DateTime.utc_now(),
    message: event["message"]
  }
end)
|> Enum.take(10)  # Take first 10 events
```

## Error Handling

Streaming operations can fail at multiple points. Handle errors appropriately:

```elixir
case API.stream_get("/events", config: config) do
  {:ok, stream_resp} ->
    try do
      stream_resp.stream
      |> Enum.each(&process_event/1)
    rescue
      e in RuntimeError ->
        Logger.error("Stream processing failed: #{Exception.message(e)}")
    end

  {:error, %Tinkex.Error{} = error} ->
    Logger.error("Failed to connect to stream: #{error.message}")
    # Check error.type for specific error categories:
    # :api_connection, :api_status, :validation
end
```

### Connection errors

Common errors when establishing streams:

- `:api_connection` - Network/transport errors, failed DNS, timeouts
- `:api_status` - HTTP error status codes (4xx, 5xx)
- `:validation` - Invalid response format

### Processing errors

Errors during stream consumption typically surface as exceptions when enumerating:

```elixir
{:ok, stream_resp} = API.stream_get("/events", config: config)

# Wrap enumeration in error handling
result =
  try do
    count =
      stream_resp.stream
      |> Enum.count()

    {:ok, count}
  rescue
    e -> {:error, e}
  end

case result do
  {:ok, count} -> IO.puts("Processed #{count} events")
  {:error, e} -> Logger.error("Stream error: #{inspect(e)}")
end
```

## Use Cases

### Real-time notifications

```elixir
# Monitor a notification stream
def monitor_notifications(config) do
  {:ok, stream} = API.stream_get("/notifications", config: config)

  stream.stream
  |> Stream.each(fn notification ->
    send_alert(notification["severity"], notification["message"])
  end)
  |> Stream.run()
end
```

### Event aggregation

```elixir
# Collect events over a time window
def collect_metrics(config, duration_ms) do
  {:ok, stream} = API.stream_get("/metrics", config: config)

  task = Task.async(fn ->
    stream.stream
    |> Enum.take_while(fn _ ->
      # Could implement time-based cutoff here
      true
    end)
    |> Enum.to_list()
  end)

  Task.await(task, duration_ms)
end
```

### Progressive data loading

```elixir
# Load large datasets progressively
def stream_dataset(config, dataset_id) do
  path = "/datasets/#{dataset_id}/stream"
  {:ok, stream} = API.stream_get(path, config: config)

  stream.stream
  |> Stream.chunk_every(100)  # Process in batches
  |> Stream.each(&process_batch/1)
  |> Stream.run()
end
```

## Current Limitations

The streaming implementation in Tinkex is intentionally minimal and focused on SSE parsing:

1. **No built-in reconnection** - Reconnection logic must be implemented by the caller
2. **No automatic retry** - Unlike regular API calls, streaming endpoints don't auto-retry
3. **Buffered delivery** - Currently `stream_get/2` buffers the full response before parsing
4. **Limited endpoint support** - Check API documentation to confirm which endpoints support streaming

For production streaming applications requiring reconnection, heartbeat monitoring, or true incremental processing, consider wrapping the SSE decoder in a GenServer or supervision tree that implements these features.

## What to read next

- API overview: `docs/guides/api_reference.md`
- Error handling and categories: `docs/guides/troubleshooting.md`
- Configuration and timeouts: `docs/guides/getting_started.md`
