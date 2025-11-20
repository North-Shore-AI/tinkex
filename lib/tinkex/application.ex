defmodule Tinkex.Application do
  @moduledoc """
  OTP application for the Tinkex SDK.

  Initializes ETS tables for shared runtime state, starts Finch pools tuned for
  the default base URL, and supervises client-facing processes. Additional pools
  can be started in the host application if multiple tenants need isolated pool
  sizing.
  """

  use Application

  @impl true
  def start(_type, _args) do
    ensure_ets_tables()

    enable_http_pools? = Application.get_env(:tinkex, :enable_http_pools, true)

    base_url =
      Application.get_env(
        :tinkex,
        :base_url,
        "https://tinker.thinkingmachines.dev/services/tinker-prod"
      )

    normalized_base = Tinkex.PoolKey.normalize_base_url(base_url)

    children =
      maybe_add_http_pool(enable_http_pools?, normalized_base) ++
        base_children()

    Supervisor.start_link(children, strategy: :one_for_one, name: Tinkex.Supervisor)
  end

  defp ensure_ets_tables do
    create_table(:tinkex_sampling_clients, [
      :set,
      :public,
      :named_table,
      read_concurrency: true
    ])

    create_table(:tinkex_rate_limiters, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    create_table(:tinkex_tokenizers, [
      :set,
      :public,
      :named_table,
      read_concurrency: true
    ])
  end

  defp create_table(name, options) do
    case :ets.whereis(name) do
      :undefined -> :ets.new(name, options)
      _ -> name
    end
  end

  defp base_children do
    [
      Tinkex.SamplingRegistry,
      {DynamicSupervisor, name: Tinkex.ClientSupervisor, strategy: :one_for_one}
    ]
  end

  defp maybe_add_http_pool(false, _normalized_base), do: []

  defp maybe_add_http_pool(true, normalized_base) do
    [
      {Finch,
       name: Tinkex.HTTP.Pool,
       pools: %{
         {normalized_base, :default} => [
           protocol: :http2,
           size: 10,
           max_idle_time: 60_000
         ],
         {normalized_base, :training} => [
           protocol: :http2,
           size: 5,
           count: 1,
           max_idle_time: 60_000
         ],
         {normalized_base, :sampling} => [
           protocol: :http2,
           size: 100,
           max_idle_time: 30_000
         ],
         {normalized_base, :session} => [
           protocol: :http2,
           size: 5,
           max_idle_time: :infinity
         ],
         {normalized_base, :futures} => [
           protocol: :http2,
           size: 50,
           max_idle_time: 60_000
         ],
         {normalized_base, :telemetry} => [
           protocol: :http2,
           size: 5,
           max_idle_time: 60_000
         ]
       }}
    ]
  end
end
