defmodule Tinkex.TestSupport.APIWorker do
  @moduledoc """
  Simple GenServer wrapper around Tinkex.API for use with Supertester.ConcurrentHarness.
  """

  use GenServer
  use Supertester.TestableGenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    {:ok, Map.new(opts)}
  end

  @impl true
  def handle_call({:post, path, payload}, from, state) do
    handle_call({:post, path, payload, []}, from, state)
  end

  @impl true
  def handle_call({:post, path, payload, extra_opts}, _from, %{config: config} = state) do
    result = Tinkex.API.post(path, payload, Keyword.put_new(extra_opts, :config, config))
    {:reply, result, state}
  end

  @impl true
  def handle_call({:get, path}, from, state) do
    handle_call({:get, path, []}, from, state)
  end

  @impl true
  def handle_call({:get, path, extra_opts}, _from, %{config: config} = state) do
    result = Tinkex.API.get(path, Keyword.put_new(extra_opts, :config, config))
    {:reply, result, state}
  end
end
