defmodule Tinkex.SamplingClientTest do
  use Tinkex.HTTPCase, async: false

  alias Tinkex.RateLimiter
  alias Tinkex.SamplingClient
  alias Tinkex.Types.{ModelInput, SampleResponse, SamplingParams}

  setup :setup_http_client

  setup do
    {:ok, _} = Application.ensure_all_started(:tinkex)
    :ok
  end

  test "registers ETS entry on init", %{bypass: bypass, config: config} do
    Bypass.expect(bypass, fn conn ->
      {:ok, _body, conn} = Plug.Conn.read_body(conn)

      case conn.request_path do
        "/api/v1/create_sampling_session" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"sampling_session_id":"sample-1"}))
      end
    end)

    {:ok, client} =
      SamplingClient.start_link(
        session_id: "sess-1",
        sampling_client_id: 0,
        base_model: "base",
        config: config
      )

    [{_, entry}] = :ets.lookup(:tinkex_sampling_clients, {:config, client})

    assert entry.sampling_session_id == "sample-1"
    assert is_reference(entry.rate_limiter)
    assert is_reference(entry.request_id_counter)
    assert entry.http_pool == config.http_pool
  end

  test "sample uses ETS config and returns typed response", %{bypass: bypass, config: config} do
    Bypass.expect(bypass, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case conn.request_path do
        "/api/v1/create_sampling_session" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"sampling_session_id":"sample-2"}))

        "/api/v1/asample" ->
          payload = Jason.decode!(body)
          assert payload["seq_id"] == 0
          assert payload["num_samples"] == 2

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, Jason.encode!(%{sequences: [%{"tokens" => [1]}]}))
      end
    end)

    {:ok, client} =
      SamplingClient.start_link(
        session_id: "sess-2",
        sampling_client_id: 0,
        base_model: "base",
        config: config,
        retry_config: [enable_retry_logic: false]
      )

    prompt = ModelInput.from_ints([1, 2, 3])
    params = %SamplingParams{max_tokens: 5, temperature: 0.7}

    {:ok, task} = SamplingClient.sample(client, prompt, params, num_samples: 2)
    assert {:ok, %SampleResponse{} = response} = Task.await(task, 5_000)
    assert length(response.sequences) == 1
  end

  test "returns validation error when ETS entry is missing" do
    prompt = ModelInput.from_ints([1])
    params = %SamplingParams{max_tokens: 1, temperature: 0.5}

    {:ok, task} = SamplingClient.sample(self(), prompt, params)
    assert {:error, %Tinkex.Error{type: :validation}} = Task.await(task, 1_000)
  end

  test "sets rate limiter backoff on 429", %{bypass: bypass, config: config} do
    Bypass.expect(bypass, fn conn ->
      {:ok, _body, conn} = Plug.Conn.read_body(conn)

      case conn.request_path do
        "/api/v1/create_sampling_session" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"sampling_session_id":"sample-rl"}))

        "/api/v1/asample" ->
          conn
          |> Plug.Conn.put_resp_header("retry-after-ms", "500")
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(429, ~s({"error":"rate"}))
      end
    end)

    {:ok, client} =
      SamplingClient.start_link(
        session_id: "sess-rl",
        sampling_client_id: 0,
        base_model: "base",
        config: config,
        retry_config: [enable_retry_logic: false]
      )

    [{_, entry}] = :ets.lookup(:tinkex_sampling_clients, {:config, client})

    prompt = ModelInput.from_ints([1])
    params = %SamplingParams{max_tokens: 1, temperature: 0.5}

    {:ok, task} = SamplingClient.sample(client, prompt, params)
    assert {:error, %Tinkex.Error{status: 429}} = Task.await(task, 5_000)
    assert RateLimiter.should_backoff?(entry.rate_limiter)
  end

  test "clients with same config share rate limiter", %{bypass: bypass, config: config} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    Bypass.expect(bypass, fn conn ->
      {:ok, _body, conn} = Plug.Conn.read_body(conn)
      idx = Agent.get_and_update(counter, &{&1, &1 + 1})

      case conn.request_path do
        "/api/v1/create_sampling_session" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"sampling_session_id":"sample-#{idx}"}))
      end
    end)

    {:ok, client1} =
      SamplingClient.start_link(
        session_id: "sess-a",
        sampling_client_id: 0,
        base_model: "base",
        config: config
      )

    {:ok, client2} =
      SamplingClient.start_link(
        session_id: "sess-b",
        sampling_client_id: 1,
        base_model: "base",
        config: config
      )

    [{_, entry1}] = :ets.lookup(:tinkex_sampling_clients, {:config, client1})
    [{_, entry2}] = :ets.lookup(:tinkex_sampling_clients, {:config, client2})

    assert entry1.rate_limiter == entry2.rate_limiter
  end

  test "compute_logprobs requests prompt logprobs and returns values",
       %{bypass: bypass, config: config} do
    Bypass.expect(bypass, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case conn.request_path do
        "/api/v1/create_sampling_session" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"sampling_session_id":"sample-logprobs"}))

        "/api/v1/asample" ->
          payload = Jason.decode!(body)
          assert payload["prompt_logprobs"] == true
          assert payload["sampling_params"]["max_tokens"] == 1
          assert payload["num_samples"] == 1

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(
            200,
            ~s({"prompt_logprobs":[-0.5, null],"sequences":[{"tokens":[1]}],"type":"sample"})
          )
      end
    end)

    {:ok, client} =
      SamplingClient.start_link(
        session_id: "sess-logprobs",
        sampling_client_id: 0,
        base_model: "base",
        config: config
      )

    prompt = ModelInput.from_ints([1, 2])

    {:ok, task} = SamplingClient.compute_logprobs(client, prompt)

    assert {:ok, [-0.5, nil]} = Task.await(task, 5_000)
  end
end
