defmodule Tinkex.TrainingClient do
  @moduledoc false

  alias Tinkex.Domain.Training.Client

  @type t :: Client.t()

  def start_link(opts \\ []), do: Client.start_link(opts)
  defdelegate child_spec(opts), to: Client

  defdelegate get_info(client), to: Client
  def get_tokenizer(client, opts \\ []), do: Client.get_tokenizer(client, opts)
  def encode(client, text, opts \\ []), do: Client.encode(client, text, opts)
  def decode(client, ids, opts \\ []), do: Client.decode(client, ids, opts)
  defdelegate unload_model(client), to: Client

  def forward_backward(client, data, loss_fn, opts \\ []),
    do: Client.forward_backward(client, data, loss_fn, opts)

  def forward(client, data, loss_fn, opts \\ []), do: Client.forward(client, data, loss_fn, opts)

  def optim_step(client, adam_params, opts \\ []),
    do: Client.optim_step(client, adam_params, opts)

  def save_weights_for_sampler(client, name, opts \\ []),
    do: Client.save_weights_for_sampler(client, name, opts)

  def save_weights_and_get_sampling_client(client, opts \\ []),
    do: Client.save_weights_and_get_sampling_client(client, opts)

  def save_weights_and_get_sampling_client_sync(client, opts \\ []),
    do: Client.save_weights_and_get_sampling_client_sync(client, opts)

  def save_state(client, name, opts \\ []), do: Client.save_state(client, name, opts)
  def load_state(client, path, opts \\ []), do: Client.load_state(client, path, opts)

  def load_state_with_optimizer(client, path, opts \\ []),
    do: Client.load_state_with_optimizer(client, path, opts)

  def create_sampling_client_async(client, model_path, opts \\ []),
    do: Client.create_sampling_client_async(client, model_path, opts)

  def forward_backward_custom(client, data, loss_fn, opts \\ []),
    do: Client.forward_backward_custom(client, data, loss_fn, opts)

  defdelegate get_telemetry(), to: Client
  defdelegate get_telemetry(client), to: Client

  def on_queue_state_change(queue_state, metadata \\ %{}),
    do: Client.on_queue_state_change(queue_state, metadata)
end
