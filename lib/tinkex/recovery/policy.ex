defmodule Tinkex.Recovery.Policy do
  @moduledoc """
  Configuration for opt-in training run recovery.

  Defaults are **disabled** and conservative: three attempts, 5s base backoff
  (capped at 60s), 30s polling interval, and optimizer state restore enabled.
  The checkpoint strategy defaults to `:latest`; `:best` is reserved for future
  support, and `{:specific, path}` targets an explicit checkpoint path.

  Telemetry events emitted by the recovery pipeline:

    * `[:tinkex, :recovery, :detected]` - monitor observed `corrupted: true`
    * `[:tinkex, :recovery, :started]` - executor attempt began
    * `[:tinkex, :recovery, :checkpoint_selected]` - checkpoint picked
    * `[:tinkex, :recovery, :client_created]` - training client created
    * `[:tinkex, :recovery, :completed]` - recovery finished successfully
    * `[:tinkex, :recovery, :failed]` - attempt failed (before exhaustion)
    * `[:tinkex, :recovery, :exhausted]` - max attempts reached, no recovery
    * `[:tinkex, :recovery, :poll_error]` - monitor failed to poll run status (keeps state)
  """

  alias Tinkex.Types.Checkpoint

  @type checkpoint_strategy :: :latest | :best | {:specific, String.t()}

  @type recovery_callback ::
          (pid() | nil, pid(), Checkpoint.t() -> :ok) | nil
  @type failure_callback :: (String.t(), term() -> :ok) | nil

  @type t :: %__MODULE__{
          enabled: boolean(),
          max_attempts: pos_integer(),
          backoff_ms: pos_integer(),
          max_backoff_ms: pos_integer(),
          poll_interval_ms: pos_integer(),
          checkpoint_strategy: checkpoint_strategy(),
          restore_optimizer: boolean(),
          on_recovery: recovery_callback(),
          on_failure: failure_callback()
        }

  defstruct enabled: false,
            max_attempts: 3,
            backoff_ms: 5_000,
            max_backoff_ms: 60_000,
            poll_interval_ms: 30_000,
            checkpoint_strategy: :latest,
            restore_optimizer: true,
            on_recovery: nil,
            on_failure: nil

  @doc """
  Build a recovery policy from a struct, keyword list, or map.

  Unknown keys are ignored; invalid values fall back to defaults to keep the
  policy conservative and opt-in.
  """
  @spec new(t() | keyword() | map() | nil) :: t()
  def new(%__MODULE__{} = policy), do: policy
  def new(nil), do: %__MODULE__{}

  @fields [
    :enabled,
    :max_attempts,
    :backoff_ms,
    :max_backoff_ms,
    :poll_interval_ms,
    :checkpoint_strategy,
    :restore_optimizer,
    :on_recovery,
    :on_failure
  ]

  def new(opts) when is_list(opts) or is_map(opts) do
    base = Map.from_struct(%__MODULE__{})

    incoming =
      opts
      |> Enum.reduce(%{}, fn {k, v}, acc ->
        key = normalize_key(k)

        if key in @fields do
          Map.put(acc, key, v)
        else
          acc
        end
      end)

    base
    |> Map.merge(incoming)
    |> normalize()
    |> then(&struct!(__MODULE__, &1))
  end

  defp normalize(map) do
    map
    |> Map.update(:enabled, false, &boolean_or_default(&1, false))
    |> Map.update(:max_attempts, 3, &positive_or_default(&1, 3))
    |> Map.update(:backoff_ms, 5_000, &positive_or_default(&1, 5_000))
    |> Map.update(:max_backoff_ms, 60_000, &positive_or_default(&1, 60_000))
    |> Map.update(:poll_interval_ms, 30_000, &positive_or_default(&1, 30_000))
    |> Map.update(:checkpoint_strategy, :latest, &normalize_strategy/1)
    |> Map.update(:restore_optimizer, true, &boolean_or_default(&1, true))
    |> Map.update(:on_recovery, nil, &maybe_on_recovery/1)
    |> Map.update(:on_failure, nil, &maybe_on_failure/1)
  end

  defp normalize_strategy({:specific, path}) when is_binary(path), do: {:specific, path}
  defp normalize_strategy(:latest), do: :latest
  defp normalize_strategy(:best), do: :best

  defp normalize_strategy(value) when is_binary(value) do
    case String.downcase(value) do
      "latest" -> :latest
      "best" -> :best
      _ -> :latest
    end
  end

  defp normalize_strategy(_), do: :latest

  defp boolean_or_default(value, _default) when is_boolean(value), do: value
  defp boolean_or_default(_, default), do: default

  defp positive_or_default(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_or_default(_value, default), do: default

  defp maybe_on_recovery(fun) when is_function(fun, 3), do: fun
  defp maybe_on_recovery(_), do: nil

  defp maybe_on_failure(fun) when is_function(fun, 2), do: fun
  defp maybe_on_failure(_), do: nil

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key) do
    case Enum.find(@fields, fn field -> Atom.to_string(field) == key end) do
      nil -> key
      field -> field
    end
  end

  defp normalize_key(other), do: other
end
