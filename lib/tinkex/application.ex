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
    heartbeat_interval_ms = Application.get_env(:tinkex, :heartbeat_interval_ms, 10_000)

    heartbeat_warning_after_ms =
      Application.get_env(:tinkex, :heartbeat_warning_after_ms, 120_000)

    base_url =
      Application.get_env(
        :tinkex,
        :base_url,
        "https://tinker.thinkingmachines.dev/services/tinker-prod"
      )

    destination = Tinkex.PoolKey.destination(base_url)

    children =
      maybe_add_http_pool(enable_http_pools?, destination) ++
        base_children(heartbeat_interval_ms, heartbeat_warning_after_ms)

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

    create_table(Tinkex.SessionManager.sessions_table(), [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])
  end

  defp create_table(name, options) do
    try do
      :ets.new(name, options)
    rescue
      ArgumentError -> name
    end
  end

  defp base_children(heartbeat_interval_ms, heartbeat_warning_after_ms) do
    [
      Tinkex.Metrics,
      Tinkex.RetrySemaphore,
      Tinkex.SamplingRegistry,
      {Task.Supervisor, name: Tinkex.TaskSupervisor},
      {Tinkex.SessionManager,
       heartbeat_interval_ms: heartbeat_interval_ms,
       heartbeat_warning_after_ms: heartbeat_warning_after_ms},
      {DynamicSupervisor, name: Tinkex.ClientSupervisor, strategy: :one_for_one}
    ]
  end

  defp maybe_add_http_pool(false, _destination), do: []

  defp maybe_add_http_pool(true, _destination) do
    [
      {Finch,
       name: Tinkex.HTTP.Pool,
       pools: %{
         default: [protocols: [:http2, :http1]]
       }}
    ]
  end
end
