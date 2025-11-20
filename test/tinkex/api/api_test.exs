defmodule Tinkex.API.APITest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.API
  alias Tinkex.Config
  alias Tinkex.Error

  import Plug.Conn

  setup do
    bypass = Bypass.open()
    finch_name = :"tinkex_api_finch_#{System.unique_integer([:positive])}"
    start_supervised!({Finch, name: finch_name})

    base_url = "http://localhost:#{bypass.port}"
    config = build_config(base_url, finch_name)

    {:ok, %{bypass: bypass, config: config, base_url: base_url, finch_name: finch_name}}
  end

  describe "post/3 retry logic" do
    test "retries on 5xx responses", %{bypass: bypass, config: config} do
      counter = start_counter()

      Bypass.expect(bypass, fn conn ->
        attempt = increment(counter)
        {:ok, _body, conn} = read_body(conn)
        conn = put_resp_content_type(conn, "application/json")

        case attempt do
          1 -> resp(conn, 500, ~s({"message":"err"}))
          2 -> resp(conn, 502, ~s({"message":"err"}))
          _ -> resp(conn, 200, ~s({"ok":true}))
        end
      end)

      assert {:ok, %{"ok" => true}} = API.post("/training", %{}, config: config)
      assert counter_value(counter) == 3
    end

    test "retries on 408 responses", %{bypass: bypass, config: config} do
      counter = start_counter()

      Bypass.expect(bypass, fn conn ->
        attempt = increment(counter)
        {:ok, _body, conn} = read_body(conn)
        conn = put_resp_content_type(conn, "application/json")

        case attempt do
          1 -> resp(conn, 408, ~s({"message":"timeout"}))
          _ -> resp(conn, 200, ~s({"ok":true}))
        end
      end)

      assert {:ok, %{"ok" => true}} = API.post("/training", %{}, config: config)
      assert counter_value(counter) == 2
    end

    test "retries on 429 with retry-after-ms header", %{bypass: bypass, config: config} do
      counter = start_counter()

      Bypass.expect(bypass, fn conn ->
        attempt = increment(counter)
        {:ok, _body, conn} = read_body(conn)
        conn = put_resp_content_type(conn, "application/json")

        case attempt do
          1 ->
            conn
            |> put_resp_header("retry-after-ms", "5")
            |> resp(429, ~s({"message":"slow down"}))

          _ ->
            resp(conn, 200, ~s({"ok":true}))
        end
      end)

      assert {:ok, %{"ok" => true}} = API.post("/training", %{}, config: config)
      assert counter_value(counter) == 2
    end

    test "parses Retry-After seconds", %{bypass: bypass, config: config} do
      counter = start_counter()

      Bypass.expect(bypass, fn conn ->
        attempt = increment(counter)
        {:ok, _body, conn} = read_body(conn)
        conn = put_resp_content_type(conn, "application/json")

        case attempt do
          1 ->
            conn
            |> put_resp_header("Retry-After", "0")
            |> resp(429, ~s({"message":"limit"}))

          _ ->
            resp(conn, 200, ~s({"ok":true}))
        end
      end)

      assert {:ok, %{"ok" => true}} = API.post("/training", %{}, config: config)
      assert counter_value(counter) == 2
    end

    test "does not retry when x-should-retry is false", %{bypass: bypass, config: config} do
      counter = start_counter()

      Bypass.expect(bypass, fn conn ->
        increment(counter)
        {:ok, _body, conn} = read_body(conn)

        conn
        |> put_resp_content_type("application/json")
        |> put_resp_header("x-should-retry", "false")
        |> resp(503, ~s({"message":"no retry"}))
      end)

      assert {:error, %Error{status: 503}} = API.post("/training", %{}, config: config)
      assert counter_value(counter) == 1
    end

    test "retries 4xx when x-should-retry is true (case insensitive)", %{
      bypass: bypass,
      config: config
    } do
      counter = start_counter()

      Bypass.expect(bypass, fn conn ->
        attempt = increment(counter)
        {:ok, _body, conn} = read_body(conn)
        conn = put_resp_content_type(conn, "application/json")

        case attempt do
          1 ->
            conn
            |> put_resp_header("X-Should-Retry", "TRUE")
            |> resp(400, ~s({"message":"retry me"}))

          _ ->
            resp(conn, 200, ~s({"ok":true}))
        end
      end)

      assert {:ok, %{"ok" => true}} = API.post("/training", %{}, config: config)
      assert counter_value(counter) == 2
    end

    test "does not retry other 4xx responses", %{bypass: bypass, config: config} do
      counter = start_counter()

      Bypass.expect(bypass, fn conn ->
        increment(counter)
        {:ok, _body, conn} = read_body(conn)

        conn
        |> put_resp_content_type("application/json")
        |> resp(404, ~s({"message":"nope"}))
      end)

      assert {:error, %Error{status: 404}} = API.post("/training", %{}, config: config)
      assert counter_value(counter) == 1
    end
  end

  describe "error handling" do
    test "parses category from response body", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, fn conn ->
        {:ok, _body, conn} = read_body(conn)

        conn
        |> put_resp_content_type("application/json")
        |> resp(400, ~s({"category":"server","message":"boom"}))
      end)

      assert {:error, %Error{category: :server}} = API.post("/training", %{}, config: config)
    end

    test "infers :user category from 4xx", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, fn conn ->
        {:ok, _body, conn} = read_body(conn)
        conn |> put_resp_content_type("application/json") |> resp(422, ~s({"message":"bad"}))
      end)

      assert {:error, %Error{category: :user}} = API.post("/training", %{}, config: config)
    end

    test "infers :server category from 5xx", %{
      bypass: bypass,
      base_url: base_url,
      finch_name: finch_name
    } do
      config = build_config(base_url, finch_name, max_retries: 0)

      Bypass.expect_once(bypass, fn conn ->
        {:ok, _body, conn} = read_body(conn)
        conn |> put_resp_content_type("application/json") |> resp(503, ~s({"message":"bad"}))
      end)

      assert {:error, %Error{category: :server}} = API.post("/training", %{}, config: config)
    end

    test "handles JSON decode errors", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, fn conn ->
        {:ok, _body, conn} = read_body(conn)
        conn |> put_resp_content_type("application/json") |> resp(200, "not-json")
      end)

      assert {:error, %Error{type: :validation}} = API.post("/training", %{}, config: config)
    end

    test "returns api_connection error for connection failures", %{config: config, bypass: bypass} do
      Bypass.down(bypass)
      assert {:error, %Error{type: :api_connection}} = API.post("/training", %{}, config: config)
    end

    test "raises when config is missing" do
      assert_raise KeyError, fn -> API.post("/training", %{}, []) end
    end
  end

  describe "get/2" do
    test "performs GET requests", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, fn conn ->
        conn
        |> put_resp_content_type("application/json")
        |> resp(200, ~s({"ok":true}))
      end)

      assert {:ok, %{"ok" => true}} = API.get("/status", config: config)
    end
  end

  defp start_counter do
    {:ok, pid} = Agent.start(fn -> 0 end)
    pid
  end

  defp increment(counter), do: Agent.get_and_update(counter, &{&1 + 1, &1 + 1})

  defp counter_value(counter), do: Agent.get(counter, & &1)

  defp build_config(base_url, finch_name, overrides \\ []) do
    previous = Application.get_env(:tinkex, :base_url)
    Application.put_env(:tinkex, :base_url, base_url)

    opts =
      [
        api_key: "test-key",
        base_url: base_url,
        http_pool: finch_name,
        timeout: Keyword.get(overrides, :timeout, 1_000),
        max_retries: Keyword.get(overrides, :max_retries, 2)
      ]
      |> Keyword.merge(overrides)

    config = Config.new(opts)

    if previous do
      Application.put_env(:tinkex, :base_url, previous)
    else
      Application.delete_env(:tinkex, :base_url)
    end

    config
  end
end
