defmodule Tinkex.Application do
  @moduledoc """
  OTP application for the Tinkex SDK.

  Starts Finch pools tuned for the default base URL. Additional pools can be
  started in the host application if multiple tenants need isolated pool sizing.
  """

  use Application

  @impl true
  def start(_type, _args) do
    if Application.get_env(:tinkex, :enable_http_pools, true) do
      start_http_pools()
    else
      Supervisor.start_link([], strategy: :one_for_one, name: Tinkex.Supervisor)
    end
  end

  defp start_http_pools do
    base_url =
      Application.get_env(
        :tinkex,
        :base_url,
        "https://tinker.thinkingmachines.dev/services/tinker-prod"
      )

    normalized_base = Tinkex.PoolKey.normalize_base_url(base_url)

    children = [
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

    Supervisor.start_link(children, strategy: :one_for_one, name: Tinkex.Supervisor)
  end
end
