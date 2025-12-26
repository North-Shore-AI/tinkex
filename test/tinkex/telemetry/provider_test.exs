defmodule Tinkex.Telemetry.ProviderTest do
  use ExUnit.Case, async: true

  alias Tinkex.Telemetry.Provider
  alias Tinkex.Telemetry.Reporter

  defmodule TestProvider do
    use Provider

    def start_link(reporter_pid) do
      Agent.start_link(fn -> reporter_pid end)
    end

    def get_telemetry(agent) do
      Agent.get(agent, & &1)
    end
  end

  defmodule OverriddenProvider do
    use Provider

    @impl Provider
    def get_telemetry do
      :custom_reporter
    end
  end

  describe "behaviour" do
    test "defines get_telemetry/0 callback" do
      callbacks = Provider.behaviour_info(:callbacks)
      assert {:get_telemetry, 0} in callbacks
    end

    test "using macro provides default implementation" do
      defmodule DefaultProvider do
        use Provider
      end

      assert function_exported?(DefaultProvider, :get_telemetry, 0)
    end

    test "default get_telemetry/0 returns nil" do
      defmodule NilProvider do
        use Provider
      end

      assert NilProvider.get_telemetry() == nil
    end

    test "can override get_telemetry/0" do
      assert OverriddenProvider.get_telemetry() == :custom_reporter
    end
  end

  describe "Tinkex.Telemetry.init/1" do
    setup do
      bypass = Bypass.open()
      finch_name = :"telemetry_provider_finch_#{System.unique_integer([:positive])}"
      {:ok, _} = start_supervised({Finch, name: finch_name})

      Bypass.stub(bypass, "POST", "/api/v1/telemetry", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status":"accepted"}))
      end)

      config =
        Tinkex.Config.new(
          api_key: "tml-test-key",
          base_url: "http://localhost:#{bypass.port}",
          http_pool: finch_name
        )

      %{config: config, bypass: bypass}
    end

    test "returns {:ok, pid} when enabled", %{config: config} do
      result =
        Tinkex.Telemetry.init(
          session_id: "test-session-#{System.unique_integer([:positive])}",
          config: config,
          enabled?: true,
          telemetry_opts: [attach_events?: false]
        )

      assert {:ok, pid} = result
      assert is_pid(pid)
      GenServer.stop(pid)
    end

    test "returns :ignore when disabled", %{config: config} do
      result =
        Tinkex.Telemetry.init(
          session_id: "test-session",
          config: config,
          enabled?: false
        )

      assert result == :ignore
    end

    test "returns :ignore when TINKER_TELEMETRY=0", %{config: config} do
      original = System.get_env("TINKER_TELEMETRY")
      System.put_env("TINKER_TELEMETRY", "0")

      try do
        result =
          Tinkex.Telemetry.init(
            session_id: "test-session-env",
            config: config,
            telemetry_opts: [attach_events?: false]
          )

        assert result == :ignore
      after
        if original do
          System.put_env("TINKER_TELEMETRY", original)
        else
          System.delete_env("TINKER_TELEMETRY")
        end
      end
    end

    test "returns {:error, reason} for missing required opts" do
      result = Tinkex.Telemetry.init([])
      assert {:error, _reason} = result
    end

    test "returns {:error, reason} for missing session_id", %{config: config} do
      result = Tinkex.Telemetry.init(config: config, enabled?: true)
      assert {:error, _reason} = result
    end

    test "returns {:error, reason} for missing config" do
      result = Tinkex.Telemetry.init(session_id: "test", enabled?: true)
      assert {:error, _reason} = result
    end

    test "treats {:error, {:already_started, pid}} as success", %{config: config} do
      session_id = "already-started-#{System.unique_integer([:positive])}"
      name = :"test_reporter_#{session_id}"

      {:ok, existing_pid} =
        Reporter.start_link(
          session_id: session_id,
          config: config,
          name: name,
          attach_events?: false,
          enabled: true
        )

      result =
        Tinkex.Telemetry.init(
          session_id: session_id,
          config: config,
          enabled?: true,
          telemetry_opts: [name: name, attach_events?: false]
        )

      assert {:ok, ^existing_pid} = result
      GenServer.stop(existing_pid)
    end

    test "passes telemetry_opts to reporter", %{config: config} do
      result =
        Tinkex.Telemetry.init(
          session_id: "opts-test-#{System.unique_integer([:positive])}",
          config: config,
          enabled?: true,
          telemetry_opts: [
            flush_interval_ms: 5_000,
            attach_events?: false
          ]
        )

      assert {:ok, pid} = result
      assert is_pid(pid)
      GenServer.stop(pid)
    end
  end

  describe "client Provider behaviour" do
    test "ServiceClient uses Provider behaviour" do
      assert {:module, _} = Code.ensure_loaded(Tinkex.ServiceClient)
      assert function_exported?(Tinkex.ServiceClient, :get_telemetry, 0)
    end

    test "TrainingClient uses Provider behaviour" do
      assert {:module, _} = Code.ensure_loaded(Tinkex.TrainingClient)
      assert function_exported?(Tinkex.TrainingClient, :get_telemetry, 0)
    end

    test "SamplingClient uses Provider behaviour" do
      assert {:module, _} = Code.ensure_loaded(Tinkex.SamplingClient)
      assert function_exported?(Tinkex.SamplingClient, :get_telemetry, 0)
    end
  end
end
