defmodule Tinkex.SamplingClientStreamTest do
  @moduledoc """
  Tests for streaming sampling functionality (sample_stream/4).
  """
  use Tinkex.HTTPCase, async: true

  alias Tinkex.SamplingClient
  alias Tinkex.Types.{ModelInput, SampleStreamChunk, SamplingParams}

  setup :setup_http_client

  setup do
    {:ok, _} = Application.ensure_all_started(:tinkex)
    :ok
  end

  describe "sample_stream/4" do
    test "streams tokens incrementally via SSE", %{bypass: bypass, config: config} do
      Bypass.expect(bypass, fn conn ->
        {:ok, _body, conn} = Plug.Conn.read_body(conn)

        case conn.request_path do
          "/api/v1/create_sampling_session" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(200, ~s({"sampling_session_id":"stream-session-1"}))

          "/api/v1/stream_sample" ->
            # SSE response with multiple chunks
            sse_body = """
            event: token
            data: {"token": "Hello", "token_id": 1, "index": 0}

            event: token
            data: {"token": " world", "token_id": 2, "index": 1}

            event: done
            data: {"finish_reason": "stop", "total_tokens": 2}

            """

            conn
            |> Plug.Conn.put_resp_content_type("text/event-stream")
            |> Plug.Conn.resp(200, sse_body)
        end
      end)

      {:ok, client} =
        SamplingClient.start_link(
          session_id: "sess-stream-1",
          sampling_client_id: 0,
          base_model: "base",
          config: config,
          retry_config: [enable_retry_logic: false]
        )

      prompt = ModelInput.from_ints([1, 2, 3])
      params = %SamplingParams{max_tokens: 10, temperature: 0.7}

      {:ok, stream} = SamplingClient.sample_stream(client, prompt, params)

      chunks = Enum.to_list(stream)

      assert length(chunks) >= 2

      [first | _rest] = chunks
      assert %SampleStreamChunk{} = first
      assert first.token == "Hello" or first.token == " world"
    end

    test "handles connection errors gracefully", %{bypass: bypass, config: config} do
      Bypass.expect(bypass, fn conn ->
        {:ok, _body, conn} = Plug.Conn.read_body(conn)

        case conn.request_path do
          "/api/v1/create_sampling_session" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(200, ~s({"sampling_session_id":"stream-session-err"}))

          "/api/v1/stream_sample" ->
            conn
            |> Plug.Conn.resp(500, "Internal Server Error")
        end
      end)

      {:ok, client} =
        SamplingClient.start_link(
          session_id: "sess-stream-err",
          sampling_client_id: 0,
          base_model: "base",
          config: config,
          retry_config: [enable_retry_logic: false]
        )

      prompt = ModelInput.from_ints([1])
      params = %SamplingParams{max_tokens: 5, temperature: 0.5}

      assert {:error, %Tinkex.Error{}} = SamplingClient.sample_stream(client, prompt, params)
    end

    test "returns validation error when client not initialized" do
      prompt = ModelInput.from_ints([1])
      params = %SamplingParams{max_tokens: 1, temperature: 0.5}

      assert {:error, %Tinkex.Error{type: :validation}} =
               SamplingClient.sample_stream(self(), prompt, params)
    end

    test "handles early stream termination", %{bypass: bypass, config: config} do
      Bypass.expect(bypass, fn conn ->
        {:ok, _body, conn} = Plug.Conn.read_body(conn)

        case conn.request_path do
          "/api/v1/create_sampling_session" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(200, ~s({"sampling_session_id":"stream-session-term"}))

          "/api/v1/stream_sample" ->
            # Single token then done
            sse_body = """
            event: token
            data: {"token": "Hi", "token_id": 1, "index": 0}

            event: done
            data: {"finish_reason": "length", "total_tokens": 1}

            """

            conn
            |> Plug.Conn.put_resp_content_type("text/event-stream")
            |> Plug.Conn.resp(200, sse_body)
        end
      end)

      {:ok, client} =
        SamplingClient.start_link(
          session_id: "sess-stream-term",
          sampling_client_id: 0,
          base_model: "base",
          config: config,
          retry_config: [enable_retry_logic: false]
        )

      prompt = ModelInput.from_ints([1])
      params = %SamplingParams{max_tokens: 1, temperature: 0.5}

      {:ok, stream} = SamplingClient.sample_stream(client, prompt, params)

      chunks = Enum.to_list(stream)
      assert length(chunks) >= 1
    end
  end
end
