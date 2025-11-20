defmodule Tinkex.API.SamplingTest do
  use Tinkex.HTTPCase, async: false

  alias Tinkex.API.Sampling

  setup :setup_http_client

  describe "sample_async/2" do
    test "calls async sampling endpoint", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/api/v1/asample", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"sequence_id":"seq-123"}))
      end)

      {:ok, result} = Sampling.sample_async(%{session_id: "s"}, config: config)
      assert result["sequence_id"] == "seq-123"
    end

    test "disables retries for sampling", %{bypass: bypass, config: config} do
      counter =
        stub_sequence(bypass, [
          {503, %{error: "nope"}, []},
          {200, %{result: "ok"}, []}
        ])

      {:error, error} = Sampling.sample_async(%{session_id: "s"}, config: config)
      assert error.status == 503
      assert Agent.get(counter, & &1) == 1
    end

    test "uses sampling pool", %{bypass: bypass, config: config} do
      attach_telemetry([[:tinkex, :http, :request, :start]])
      stub_success(bypass, %{result: "ok"})

      {:ok, _} = Sampling.sample_async(%{session_id: "abc"}, config: config)

      assert_receive {:telemetry, [:tinkex, :http, :request, :start], _,
                      %{pool_type: :sampling, path: "/api/v1/asample"}}
    end
  end
end
