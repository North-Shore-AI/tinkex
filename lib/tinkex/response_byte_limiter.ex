defmodule Tinkex.ResponseByteLimiter do
  @moduledoc false

  alias Tinkex.{BytesSemaphore, Config, PoolKey}

  @table :tinkex_response_byte_limiters
  @default_max_bytes 5 * 1024 * 1024

  @spec with_bytes(Config.t(), non_neg_integer(), (-> result)) :: result when result: any()
  def with_bytes(%Config{} = config, bytes, fun)
      when is_integer(bytes) and bytes >= 0 and is_function(fun, 0) do
    BytesSemaphore.with_bytes(for_config(config), bytes, fun)
  end

  @spec for_config(Config.t()) :: BytesSemaphore.t()
  def for_config(%Config{base_url: base_url, api_key: api_key}) do
    key = {:response_bytes, {PoolKey.normalize_base_url(base_url), api_key}}
    ensure_table!()

    case alive_limiter(key) do
      {:ok, limiter} -> limiter
      :error -> create_limiter(key)
    end
  end

  defp create_limiter(key) do
    {:ok, limiter} = BytesSemaphore.start_link(max_bytes: @default_max_bytes)
    Process.unlink(limiter)

    case :ets.insert_new(@table, {key, limiter}) do
      true ->
        limiter

      false ->
        maybe_replace_limiter(key, limiter)
    end
  end

  defp maybe_replace_limiter(key, limiter) do
    case alive_limiter(key) do
      {:ok, existing} ->
        Process.exit(limiter, :normal)
        existing

      :error ->
        :ets.insert(@table, {key, limiter})
        limiter
    end
  end

  defp alive_limiter(key) do
    case :ets.lookup(@table, key) do
      [{^key, limiter}] when is_pid(limiter) ->
        if Process.alive?(limiter), do: {:ok, limiter}, else: :error

      _ ->
        :error
    end
  end

  defp ensure_table! do
    :ets.new(@table, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])
  rescue
    ArgumentError -> @table
  end
end
