defmodule Tinkex.Integration.SamplingWorkflowTest do
  use Tinkex.HTTPCase, async: true

  alias Tinkex.{RateLimiter, SamplingClient, ServiceClient}
  alias Tinkex.Types.{ModelInput, SampleResponse, SamplingParams}

  setup :setup_http_client

  setup do
    {:ok, _} = Application.ensure_all_started(:tinkex)
    :ok
  end

  setup %{config: config} do
    {config.base_url, config.api_key}
    |> RateLimiter.for_key()
    |> RateLimiter.clear_backoff()

    :ok
  end

  test "creates sampling client and returns sample response", %{bypass: bypass, config: config} do
    Bypass.expect(bypass, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case conn.request_path do
        "/api/v1/create_session" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"session_id":"session-sample"}))

        "/api/v1/session_heartbeat" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"ok":true}))

        "/api/v1/create_sampling_session" ->
          payload = Jason.decode!(body)
          assert payload["session_id"] == "session-sample"
          assert payload["base_model"] == "base-model"

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"sampling_session_id":"sample-session"}))

        "/api/v1/asample" ->
          payload = Jason.decode!(body)
          assert payload["sampling_session_id"] == "sample-session"
          assert payload["seq_id"] == 0
          assert payload["num_samples"] == 2

          response = %{
            sequences: [
              %{"tokens" => [10, 11, 12], "logprobs" => [-0.1, -0.2], "stop_reason" => "length"}
            ],
            prompt_logprobs: [-0.05],
            topk_prompt_logprobs: [[[42, -0.3]]]
          }

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, Jason.encode!(response))

        _ ->
          flunk("Unexpected request to #{conn.request_path}")
      end
    end)

    {:ok, service} = ServiceClient.start_link(config: config)

    {:ok, sampling_client} =
      ServiceClient.create_sampling_client(service,
        base_model: "base-model",
        retry_config: [enable_retry_logic: false]
      )

    prompt = ModelInput.from_ints([1, 2, 3])
    params = %SamplingParams{max_tokens: 4, temperature: 0.4}

    {:ok, task} = SamplingClient.sample(sampling_client, prompt, params, num_samples: 2)
    assert {:ok, %SampleResponse{} = response} = Task.await(task, 5_000)

    assert Enum.map(response.sequences, & &1.tokens) == [[10, 11, 12]]
    assert Enum.map(response.sequences, & &1.stop_reason) == [:length]
    assert response.prompt_logprobs == [-0.05]
    assert response.topk_prompt_logprobs == [[{42, -0.3}]]

    GenServer.stop(service)
  end

  test "backs off after 429 across concurrent sampling tasks", %{bypass: bypass, config: config} do
    call_log = start_supervised!({Agent, fn -> [] end})

    Bypass.expect(bypass, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case conn.request_path do
        "/api/v1/create_session" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"session_id":"session-rate"}))

        "/api/v1/session_heartbeat" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"ok":true}))

        "/api/v1/create_sampling_session" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"sampling_session_id":"sample-rate"}))

        "/api/v1/asample" ->
          payload = Jason.decode!(body)

          call_count =
            Agent.get_and_update(call_log, fn calls ->
              timestamp = System.monotonic_time(:millisecond)
              entry = %{ts: timestamp, seq_id: payload["seq_id"], path: conn.request_path}
              {length(calls), calls ++ [entry]}
            end)

          conn = Plug.Conn.assign(conn, :call_count, call_count)

          case call_count do
            0 ->
              conn
              |> Plug.Conn.put_resp_header("retry-after-ms", "200")
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.resp(429, ~s({"error":"rate"}))

            _ ->
              response = %{sequences: [%{"tokens" => [call_count]}]}

              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.resp(200, Jason.encode!(response))
          end

        _ ->
          flunk("Unexpected request to #{conn.request_path}")
      end
    end)

    {:ok, service} = ServiceClient.start_link(config: config)

    {:ok, sampling_client} =
      ServiceClient.create_sampling_client(service,
        base_model: "base-model",
        retry_config: [enable_retry_logic: false]
      )

    prompt = ModelInput.from_ints([1])
    params = %SamplingParams{max_tokens: 2, temperature: 0.2}

    {:ok, first_task} = SamplingClient.sample(sampling_client, prompt, params)
    assert {:error, %Tinkex.Error{status: 429}} = Task.await(first_task, 5_000)

    [{_, entry}] = :ets.lookup(:tinkex_sampling_clients, {:config, sampling_client})
    backoff_until = :atomics.get(entry.rate_limiter, 1)
    assert RateLimiter.should_backoff?(entry.rate_limiter)

    tasks =
      for _ <- 1..20 do
        {:ok, task} = SamplingClient.sample(sampling_client, prompt, params)
        task
      end

    results = Task.await_many(tasks, 5_000)

    assert Enum.all?(results, fn
             {:ok, %SampleResponse{}} -> true
             _ -> false
           end)

    log = Agent.get(call_log, & &1)
    assert length(log) == 21

    seq_ids = log |> Enum.map(& &1.seq_id) |> Enum.sort()
    assert seq_ids == Enum.to_list(0..20)

    min_after_backoff = log |> Enum.drop(1) |> Enum.map(& &1.ts) |> Enum.min()
    assert min_after_backoff >= backoff_until
    refute RateLimiter.should_backoff?(entry.rate_limiter)

    GenServer.stop(service)
  end

  test "surface server and user errors without retries", %{bypass: bypass, config: config} do
    counter = start_supervised!({Agent, fn -> 0 end})

    Bypass.expect(bypass, fn conn ->
      {:ok, _body, conn} = Plug.Conn.read_body(conn)

      case conn.request_path do
        "/api/v1/create_session" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"session_id":"session-errors"}))

        "/api/v1/session_heartbeat" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"ok":true}))

        "/api/v1/create_sampling_session" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"sampling_session_id":"sample-errors"}))

        "/api/v1/asample" ->
          call_count = Agent.get_and_update(counter, &{&1, &1 + 1})
          conn = Plug.Conn.assign(conn, :call_count, call_count)

          case call_count do
            0 ->
              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.resp(500, ~s({"error":"boom"}))

            1 ->
              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.resp(400, ~s({"error":"invalid","category":"user"}))
          end

        _ ->
          flunk("Unexpected request to #{conn.request_path}")
      end
    end)

    {:ok, service} = ServiceClient.start_link(config: config)

    {:ok, sampling_client} =
      ServiceClient.create_sampling_client(service,
        base_model: "base-model",
        retry_config: [enable_retry_logic: false]
      )

    prompt = ModelInput.from_ints([1])
    params = %SamplingParams{max_tokens: 1, temperature: 0.5}

    {:ok, server_error_task} = SamplingClient.sample(sampling_client, prompt, params)

    assert {:error, %Tinkex.Error{type: :api_status, status: 500}} =
             Task.await(server_error_task, 5_000)

    assert Agent.get(counter, & &1) == 1

    {:ok, user_error_task} = SamplingClient.sample(sampling_client, prompt, params)

    assert {:error, %Tinkex.Error{type: :api_status, status: 400, category: :user}} =
             Task.await(user_error_task, 5_000)

    assert Agent.get(counter, & &1) == 2

    [{_, entry}] = :ets.lookup(:tinkex_sampling_clients, {:config, sampling_client})
    assert :atomics.get(entry.rate_limiter, 1) == 0

    GenServer.stop(service)
  end

  test "multi-client sampling keeps rate limiters isolated", %{
    bypass: bypass_a,
    config: config_a,
    finch_name: finch_name
  } do
    bypass_b = Bypass.open()

    on_exit(fn ->
      try do
        Bypass.down(bypass_b)
      rescue
        _ -> :ok
      end
    end)

    call_log = start_supervised!({Agent, fn -> %{a: [], b: []} end})

    Bypass.expect(bypass_a, fn conn ->
      {:ok, _body, conn} = Plug.Conn.read_body(conn)

      case conn.request_path do
        "/api/v1/create_session" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"session_id":"session-a"}))

        "/api/v1/session_heartbeat" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"ok":true}))

        "/api/v1/create_sampling_session" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"sampling_session_id":"sample-a"}))

        "/api/v1/asample" ->
          Agent.update(call_log, fn log ->
            update_in(log[:a], &(&1 ++ [System.monotonic_time(:millisecond)]))
          end)

          conn
          |> Plug.Conn.put_resp_header("retry-after-ms", "400")
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(429, ~s({"error":"rate"}))

        _ ->
          flunk("Unexpected request to #{conn.request_path}")
      end
    end)

    Bypass.expect(bypass_b, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case conn.request_path do
        "/api/v1/create_session" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"session_id":"session-b"}))

        "/api/v1/session_heartbeat" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"ok":true}))

        "/api/v1/create_sampling_session" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"sampling_session_id":"sample-b"}))

        "/api/v1/asample" ->
          Agent.update(call_log, fn log ->
            update_in(log[:b], &(&1 ++ [System.monotonic_time(:millisecond)]))
          end)

          payload = Jason.decode!(body)
          conn = Plug.Conn.assign(conn, :call_count, 0)

          assert payload["sampling_session_id"] == "sample-b"

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"sequences":[{"tokens":[99]}]}))

        _ ->
          flunk("Unexpected request to #{conn.request_path}")
      end
    end)

    config_b =
      Tinkex.Config.new(
        api_key: "tml-other-key",
        base_url: endpoint_url(bypass_b),
        http_pool: finch_name
      )

    {:ok, service_a} = ServiceClient.start_link(config: config_a)
    {:ok, service_b} = ServiceClient.start_link(config: config_b)

    {:ok, client_a} =
      ServiceClient.create_sampling_client(service_a,
        base_model: "base-a",
        retry_config: [enable_retry_logic: false]
      )

    {:ok, client_b} =
      ServiceClient.create_sampling_client(service_b,
        base_model: "base-b",
        retry_config: [enable_retry_logic: false]
      )

    prompt = ModelInput.from_ints([7])
    params = %SamplingParams{max_tokens: 2, temperature: 0.2}

    {:ok, task_a} = SamplingClient.sample(client_a, prompt, params)
    assert {:error, %Tinkex.Error{status: 429}} = Task.await(task_a, 5_000)

    [{_, entry_a}] = :ets.lookup(:tinkex_sampling_clients, {:config, client_a})
    [{_, entry_b}] = :ets.lookup(:tinkex_sampling_clients, {:config, client_b})

    refute entry_a.rate_limiter == entry_b.rate_limiter
    assert RateLimiter.should_backoff?(entry_a.rate_limiter)
    refute RateLimiter.should_backoff?(entry_b.rate_limiter)

    backoff_until = :atomics.get(entry_a.rate_limiter, 1)

    {:ok, task_b} = SamplingClient.sample(client_b, prompt, params)
    assert {:ok, %SampleResponse{}} = Task.await(task_b, 5_000)

    call_b_time =
      Agent.get(call_log, fn log ->
        log[:b] |> List.first()
      end)

    assert is_integer(call_b_time)
    assert call_b_time < backoff_until

    GenServer.stop(service_a)
    GenServer.stop(service_b)
  end
end
