defmodule Tinkex.Integration.MultiClientConcurrencyTest do
  use Tinkex.HTTPCase, async: false

  alias Tinkex.{
    PoolKey,
    RateLimiter,
    SamplingClient,
    ServiceClient,
    TrainingClient
  }

  alias Tinkex.Types.{AdamParams, Datum, ModelInput, SampleResponse, SamplingParams}

  setup :setup_http_client

  setup do
    {:ok, _} = Application.ensure_all_started(:tinkex)
    :ok
  end

  test "two clients train and sample concurrently without cross-talk", %{
    bypass: bypass_a,
    config: config_a,
    finch_name: _finch_a
  } do
    bypass_b = Bypass.open()
    finch_b = :"tinkex_test_finch_#{System.unique_integer([:positive])}"

    start_supervised!({Finch, name: finch_b})

    config_b =
      Tinkex.Config.new(
        api_key: "other-key",
        base_url: endpoint_url(bypass_b),
        http_pool: finch_b
      )

    on_exit(fn ->
      Enum.each([bypass_b], fn bp ->
        try do
          Bypass.down(bp)
        rescue
          _ -> :ok
        end
      end)
    end)

    {:ok, training_log} = Agent.start_link(fn -> %{fw: %{}, future: %{}} end)
    {:ok, sample_log} = Agent.start_link(fn -> %{a: [], b: []} end)
    {:ok, sample_counts} = Agent.start_link(fn -> %{a: 0, b: 0} end)
    {:ok, telemetry_log} = Agent.start_link(fn -> %{counts: %{}, stop_events: 0} end)

    on_exit(fn ->
      for agent <- [training_log, sample_log, sample_counts, telemetry_log],
          Process.alive?(agent) do
        Agent.stop(agent, :normal)
      end
    end)

    increment_call = fn agent, bucket, id ->
      Agent.get_and_update(agent, fn state ->
        bucket_map = Map.get(state, bucket, %{})
        current = Map.get(bucket_map, id, 0)
        updated = Map.put(bucket_map, id, current + 1)
        {current, Map.put(state, bucket, updated)}
      end)
    end

    next_sample = fn agent, bucket ->
      Agent.get_and_update(agent, fn state ->
        current = Map.get(state, bucket, 0)
        {current, Map.put(state, bucket, current + 1)}
      end)
    end

    log_sample_time = fn bucket ->
      Agent.update(sample_log, fn log ->
        update_in(log[bucket], &(&1 ++ [System.monotonic_time(:millisecond)]))
      end)
    end

    telemetry_handler =
      "multi-client-http-#{:erlang.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        telemetry_handler,
        [:tinkex, :http, :request, :stop],
        fn _event, measurements, metadata, _ ->
          if Process.alive?(telemetry_log) do
            duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

            Agent.update(telemetry_log, fn %{counts: counts, stop_events: stop} ->
              counts = Map.update(counts, metadata.base_url, 1, &(&1 + 1))

              %{
                counts: counts,
                stop_events: stop + 1,
                last_duration: duration_ms
              }
            end)
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(telemetry_handler) end)

    Bypass.expect(bypass_a, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case conn.request_path do
        "/api/v1/session_heartbeat" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"ok":true}))

        "/api/v1/create_session" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"session_id":"session-a"}))

        "/api/v1/create_model" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"model_id":"model-a"}))

        "/api/v1/create_sampling_session" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"sampling_session_id":"sampling-a"}))

        "/api/v1/forward_backward" ->
          call_idx = increment_call.(training_log, :fw, :a)

          case call_idx do
            0 ->
              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.resp(500, ~s({"error":"flaky-a"}))

            _ ->
              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.resp(200, ~s({"request_id":"fw-a"}))
          end

        "/api/v1/optim_step" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"request_id":"opt-a"}))

        "/api/v1/retrieve_future" ->
          payload = Jason.decode!(body)
          request_id = payload["request_id"]
          call_idx = increment_call.(training_log, :future, request_id)

          cond do
            request_id == "fw-a" and call_idx == 0 ->
              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.resp(500, ~s({"error":"poll-rate"}))

            request_id == "fw-a" ->
              response = %{
                status: "completed",
                result: %{
                  "loss_fn_output_type" => "mean",
                  "loss_fn_outputs" => [%{"chunk" => 0}],
                  "metrics" => %{"loss" => 1.0}
                }
              }

              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.resp(200, Jason.encode!(response))

            request_id == "opt-a" ->
              response = %{status: "completed", result: %{"metrics" => %{"lr" => 0.02}}}

              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.resp(200, Jason.encode!(response))

            true ->
              flunk("Unexpected future request on bypass A: #{inspect(request_id)}")
          end

        "/api/v1/asample" ->
          call_idx = next_sample.(sample_counts, :a)

          case call_idx do
            0 ->
              conn
              |> Plug.Conn.put_resp_header("retry-after-ms", "75")
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.resp(429, ~s({"error":"rate-a"}))

            _ ->
              log_sample_time.(:a)
              payload = Jason.decode!(body)

              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.resp(
                200,
                Jason.encode!(%{
                  "sequences" => [
                    %{"tokens" => [payload["seq_id"]], "stop_reason" => "length"}
                  ]
                })
              )
          end

        _ ->
          flunk("Unexpected request to #{conn.request_path} on bypass A")
      end
    end)

    Bypass.expect(bypass_b, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case conn.request_path do
        "/api/v1/session_heartbeat" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"ok":true}))

        "/api/v1/create_session" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"session_id":"session-b"}))

        "/api/v1/create_model" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"model_id":"model-b"}))

        "/api/v1/create_sampling_session" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"sampling_session_id":"sampling-b"}))

        "/api/v1/forward_backward" ->
          increment_call.(training_log, :fw, :b)

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"request_id":"fw-b"}))

        "/api/v1/optim_step" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"request_id":"opt-b"}))

        "/api/v1/retrieve_future" ->
          payload = Jason.decode!(body)
          request_id = payload["request_id"]
          call_idx = increment_call.(training_log, :future, request_id)

          response =
            case request_id do
              "fw-b" ->
                case call_idx do
                  0 -> %{status: "pending"}
                  _ -> %{status: "completed", result: %{"metrics" => %{"loss" => 0.5}}}
                end

              "opt-b" ->
                %{status: "completed", result: %{"metrics" => %{"lr" => 0.01}}}

              other ->
                flunk("Unexpected future request on bypass B: #{inspect(other)}")
            end

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, Jason.encode!(response))

        "/api/v1/asample" ->
          call_idx = next_sample.(sample_counts, :b)
          log_sample_time.(:b)
          _payload = Jason.decode!(body)

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(
            200,
            Jason.encode!(%{
              "sequences" => [
                %{"tokens" => [1_000 + call_idx], "stop_reason" => "stop"}
              ]
            })
          )

        _ ->
          flunk("Unexpected request to #{conn.request_path} on bypass B")
      end
    end)

    {:ok, service_a} = ServiceClient.start_link(config: config_a)
    {:ok, service_b} = ServiceClient.start_link(config: config_b)

    {:ok, training_a} = ServiceClient.create_lora_training_client(service_a, base_model: "base-a")
    {:ok, training_b} = ServiceClient.create_lora_training_client(service_b, base_model: "base-b")

    {:ok, sampler_a} =
      ServiceClient.create_sampling_client(service_a,
        base_model: "sample-a",
        retry_config: [enable_retry_logic: false]
      )

    {:ok, sampler_b} =
      ServiceClient.create_sampling_client(service_b,
        base_model: "sample-b",
        retry_config: [enable_retry_logic: false]
      )

    data =
      Enum.map(1..4, fn idx ->
        %Datum{model_input: ModelInput.from_ints([idx])}
      end)

    prompt = ModelInput.from_ints([9])
    params = %SamplingParams{max_tokens: 2, temperature: 0.2}

    {:ok, first_error_task} = SamplingClient.sample(sampler_a, prompt, params)
    assert {:error, %Tinkex.Error{status: 429}} = Task.await(first_error_task, 5_000)

    [{_, entry_a}] = :ets.lookup(:tinkex_sampling_clients, {:config, sampler_a})
    [{_, entry_b}] = :ets.lookup(:tinkex_sampling_clients, {:config, sampler_b})

    normalized_a = PoolKey.normalize_base_url(config_a.base_url)
    normalized_b = PoolKey.normalize_base_url(config_b.base_url)

    assert [{_, limiter_a}] =
             :ets.lookup(:tinkex_rate_limiters, {:limiter, {normalized_a, config_a.api_key}})

    assert [{_, limiter_b}] =
             :ets.lookup(:tinkex_rate_limiters, {:limiter, {normalized_b, config_b.api_key}})

    refute limiter_a == limiter_b
    refute entry_a.rate_limiter == entry_b.rate_limiter

    backoff_until = :atomics.get(entry_a.rate_limiter, 1)
    assert RateLimiter.should_backoff?(entry_a.rate_limiter)

    training_tasks =
      for {training, tag} <- [{training_a, :a}, {training_b, :b}] do
        Task.async(fn ->
          {:ok, fb_task} =
            TrainingClient.forward_backward(training, data, :cross_entropy,
              sleep_fun: fn _ -> :ok end
            )

          {:ok, _fb} = Task.await(fb_task, 5_000)

          {:ok, opt_task} =
            TrainingClient.optim_step(training, %AdamParams{learning_rate: 0.02})

          {:ok, _opt} = Task.await(opt_task, 5_000)
          tag
        end)
      end

    total_a_requests = 60
    total_b_requests = 60

    sample_tasks_a =
      for _ <- 1..total_a_requests do
        {:ok, task} = SamplingClient.sample(sampler_a, prompt, params)
        task
      end

    sample_tasks_b =
      for _ <- 1..total_b_requests do
        {:ok, task} = SamplingClient.sample(sampler_b, prompt, params)
        task
      end

    results_a = Task.await_many(sample_tasks_a, 5_000)
    results_b = Task.await_many(sample_tasks_b, 5_000)
    assert Enum.all?(results_a, &match?({:ok, %SampleResponse{}}, &1))
    assert Enum.all?(results_b, &match?({:ok, %SampleResponse{}}, &1))

    training_results = Task.await_many(training_tasks, 10_000)
    assert Enum.sort(training_results) == [:a, :b]

    refute RateLimiter.should_backoff?(entry_a.rate_limiter)
    refute RateLimiter.should_backoff?(entry_b.rate_limiter)
    assert :atomics.get(entry_a.rate_limiter, 1) == 0
    assert :atomics.get(entry_b.rate_limiter, 1) == 0

    min_a_time =
      Agent.get(sample_log, fn log ->
        log[:a] |> Enum.min()
      end)

    first_b_time =
      Agent.get(sample_log, fn log ->
        log[:b] |> Enum.min()
      end)

    assert min_a_time >= backoff_until
    assert first_b_time < backoff_until

    training_calls = Agent.get(training_log, & &1)
    assert training_calls.fw[:a] == 2
    assert training_calls.fw[:b] == 1
    assert training_calls.future["fw-a"] == 2
    assert training_calls.future["fw-b"] == 2
    assert training_calls.future["opt-a"] == 1
    assert training_calls.future["opt-b"] == 1

    telemetry_counts = Agent.get(telemetry_log, & &1)
    assert telemetry_counts.stop_events >= total_a_requests + total_b_requests
    assert Map.has_key?(telemetry_counts.counts, config_a.base_url)
    assert Map.has_key?(telemetry_counts.counts, config_b.base_url)

    GenServer.stop(service_a)
    GenServer.stop(service_b)
  end
end
