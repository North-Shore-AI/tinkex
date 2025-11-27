# Impact of the heartbeat gap

- Sessions created by Elixir likely time out on the server because heartbeats 404.
- Long-running training/sampling sessions may be reclaimed silently; subsequent calls may fail unpredictably.
- Local test suite gives false confidence because it stubs the wrong path.
- No telemetry or logging warns users of missed heartbeats in Elixir; issues surface only as later API errors.
- Multi-client flows (Service → Training/Sampling) depend on a live session; without heartbeats they can be evicted mid-run.
