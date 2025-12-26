defmodule Tinkex.Application do
  @moduledoc """
  OTP application for the Tinkex SDK.

  Initializes ETS tables for shared runtime state, starts Finch pools tuned for
  the default base URL, and supervises client-facing processes. Additional pools
  can be started in the host application if multiple tenants need isolated pool
  sizing.

  ## Pool Configuration (Python Parity)

  Python SDK uses `httpx.Limits(max_connections=1000, max_keepalive_connections=20)`.
  Tinkex configures Finch pools to approximate these limits:

  - `pool_size` - connections per pool (default: 50, env: `TINKEX_POOL_SIZE`)
  - `pool_count` - number of pools (default: 20, env: `TINKEX_POOL_COUNT`)
  - Total connections = pool_size * pool_count = 1000 (matching Python's max_connections)

  Override via application config or environment variables:

      # config.exs
      config :tinkex,
        pool_size: 100,
        pool_count: 10

      # Environment variables
      export TINKEX_POOL_SIZE=100
      export TINKEX_POOL_COUNT=10
  """

  use Application

  alias Tinkex.Env
  alias Tinkex.Logging
  alias Tinkex.PoolKey

  # Python SDK parity: max_connections=1000, max_keepalive_connections=20
  # Finch: size=50, count=20 gives 50*20=1000 total connections per destination
  @default_pool_size 50
  @default_pool_count 20

  @impl true
  def start(_type, _args) do
    ensure_ets_tables()

    env = Env.snapshot()
    apply_log_level(env)

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

    base_pool_name =
      Application.get_env(
        :tinkex,
        :http_pool,
        env.http_pool || Tinkex.HTTP.Pool
      )

    # Pool configuration: env > app config > defaults (Python parity defaults)
    pool_size = env.pool_size || Application.get_env(:tinkex, :pool_size, @default_pool_size)
    pool_count = env.pool_count || Application.get_env(:tinkex, :pool_count, @default_pool_count)

    pool_overrides =
      case Application.get_env(:tinkex, :pool_overrides) do
        value when is_map(value) -> value
        _ -> %{}
      end

    pool_map = build_pool_map(base_url, pool_size, pool_count, pool_overrides, base_pool_name)

    children =
      maybe_add_http_pool(enable_http_pools?, pool_map) ++
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
    :ets.new(name, options)
  rescue
    ArgumentError -> name
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

  defp maybe_add_http_pool(false, _pool_map), do: []

  defp maybe_add_http_pool(true, pool_map) do
    Enum.map(pool_map, fn {_type, %{name: name, pools: pools}} ->
      {Finch, name: name, pools: pools}
    end)
  end

  @doc false
  def build_pool_map(
        base_url,
        pool_size,
        pool_count,
        pool_overrides,
        base_pool_name \\ Tinkex.HTTP.Pool
      ) do
    conn_opts = build_conn_opts()
    sampling_opts = pool_opts(pool_size, pool_count, conn_opts)
    destination = PoolKey.destination(base_url)

    pools =
      %{
        session: override_pool_opts(pool_opts(5, 1, conn_opts), pool_overrides[:session]),
        training: override_pool_opts(pool_opts(5, 2, conn_opts), pool_overrides[:training]),
        sampling: override_pool_opts(sampling_opts, pool_overrides[:sampling]),
        futures:
          override_pool_opts(
            pool_opts(max(div(pool_size, 2), 1), max(div(pool_count, 2), 1), conn_opts),
            pool_overrides[:futures]
          ),
        telemetry: override_pool_opts(pool_opts(5, 1, conn_opts), pool_overrides[:telemetry]),
        default: sampling_opts
      }

    Enum.into(pools, %{}, fn
      {:default, opts} ->
        {:default, %{name: base_pool_name, pools: %{destination => opts}}}

      {type, opts} ->
        {type,
         %{
           name: PoolKey.pool_name(base_pool_name, base_url, type),
           pools: %{destination => opts}
         }}
    end)
  end

  defp pool_opts(size, count, conn_opts) do
    base_opts = [
      protocols: [:http2, :http1],
      size: size,
      count: count
    ]

    if conn_opts == [] do
      base_opts
    else
      Keyword.put(base_opts, :conn_opts, conn_opts)
    end
  end

  defp override_pool_opts(opts, nil), do: opts

  defp override_pool_opts(opts, overrides) when is_map(overrides),
    do: override_pool_opts(opts, Map.to_list(overrides))

  defp override_pool_opts(opts, overrides) when is_list(overrides) do
    Keyword.merge(opts, overrides)
  end

  defp override_pool_opts(opts, _), do: opts

  defp build_conn_opts do
    proxy = Application.get_env(:tinkex, :proxy)
    proxy_headers = Application.get_env(:tinkex, :proxy_headers, [])

    opts = []
    opts = if proxy, do: [{:proxy, proxy} | opts], else: opts
    opts = if proxy_headers != [], do: [{:proxy_headers, proxy_headers} | opts], else: opts
    opts
  end

  @doc """
  Returns the default pool size.
  """
  @spec default_pool_size() :: pos_integer()
  def default_pool_size, do: @default_pool_size

  @doc """
  Returns the default pool count.
  """
  @spec default_pool_count() :: pos_integer()
  def default_pool_count, do: @default_pool_count

  defp apply_log_level(env) do
    startup_level = Application.get_env(:tinkex, :log_level) || env.log_level
    Logging.maybe_set_level(startup_level)
  end
end
