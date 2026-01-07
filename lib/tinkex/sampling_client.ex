defmodule Tinkex.SamplingClient do
  @moduledoc false

  alias Tinkex.Domain.Sampling.Client

  def start_link(opts \\ []), do: Client.start_link(opts)
  defdelegate child_spec(opts), to: Client

  def create_async(service_client, opts \\ []), do: Client.create_async(service_client, opts)

  def sample(client, prompt, sampling_params, opts \\ []),
    do: Client.sample(client, prompt, sampling_params, opts)

  def sample_stream(client, prompt, sampling_params, opts \\ []),
    do: Client.sample_stream(client, prompt, sampling_params, opts)

  def compute_logprobs(client, prompt, opts \\ []),
    do: Client.compute_logprobs(client, prompt, opts)

  defdelegate get_telemetry(), to: Client
  defdelegate get_telemetry(client), to: Client

  def on_queue_state_change(queue_state, metadata \\ %{}),
    do: Client.on_queue_state_change(queue_state, metadata)

  defdelegate clear_queue_state_debounce(session_id), to: Client
end
