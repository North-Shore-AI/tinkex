defmodule Tinkex.API.Headers do
  @moduledoc """
  HTTP header building and management for Tinkex API requests.

  Handles:
  - Standard headers (accept, content-type, user-agent, etc.)
  - Authentication headers (API key)
  - Stainless SDK headers
  - Cloudflare Access headers
  - Request-specific headers (idempotency, sampling, retry count)
  - OpenTelemetry trace context propagation (opt-in)
  - Header deduplication
  """

  alias Tinkex.Config
  alias Tinkex.Env
  alias Tinkex.Telemetry.Otel

  @doc """
  Builds complete headers list for a request.

  Combines headers from multiple sources in priority order:
  1. Standard headers (accept, content-type, etc.)
  2. Stainless SDK headers
  3. Cloudflare Access headers
  4. Config default headers
  5. Request-specific headers
  6. Method-specific headers (idempotency, sampling)
  7. User-provided headers from opts
  8. OpenTelemetry trace context (if enabled)

  Lower priority headers are overridden by higher priority ones.
  """
  @spec build(atom(), Config.t(), keyword(), timeout()) :: [{String.t(), String.t()}]
  def build(method, config, opts, timeout_ms) do
    [
      {"accept", "application/json"},
      {"content-type", "application/json"},
      {"user-agent", user_agent()},
      {"connection", "keep-alive"},
      {"accept-encoding", "gzip"},
      {"x-api-key", config.api_key}
    ]
    |> Kernel.++(stainless_headers(timeout_ms))
    |> Kernel.++(cloudflare_headers(config))
    |> Kernel.++(config_default_headers(config))
    |> Kernel.++(request_headers(opts))
    |> Kernel.++(idempotency_headers(method, opts))
    |> Kernel.++(sampling_headers(opts))
    |> Kernel.++(maybe_raw_response_header(opts))
    |> Kernel.++(Keyword.get(opts, :headers, []))
    |> Otel.inject_headers(config)
    |> dedupe()
  end

  @doc """
  Adds or updates retry-related headers to a request.

  Sets:
  - x-stainless-retry-count: Current retry attempt number
  - x-stainless-read-timeout: Request timeout (if not already set)
  """
  @spec put_retry_headers(Finch.Request.t(), non_neg_integer(), timeout()) ::
          Finch.Request.t()
  def put_retry_headers(%Finch.Request{} = request, attempt, timeout_ms) do
    headers =
      request.headers
      |> put("x-stainless-retry-count", Integer.to_string(attempt))
      |> ensure_read_timeout(timeout_ms)

    %{request | headers: headers}
  end

  @doc """
  Adds or replaces a header in the headers list.

  Case-insensitive replacement - if a header with the same name exists
  (regardless of case), it will be replaced.
  """
  @spec put([{String.t(), String.t()}], String.t(), String.t()) :: [
          {String.t(), String.t()}
        ]
  def put(headers, name, value) do
    name_downcase = String.downcase(name)

    headers
    |> Enum.reject(fn {k, _} -> String.downcase(k) == name_downcase end)
    |> List.insert_at(-1, {name, value})
  end

  @doc """
  Retrieves a header value by name (case-insensitive).

  Returns the lowercased and trimmed value if found, nil otherwise.
  """
  @spec get_normalized([{String.t(), String.t()}], String.t()) :: String.t() | nil
  def get_normalized(headers, name) do
    name_lower = String.downcase(name)

    headers
    |> Enum.find_value(fn {k, v} ->
      if String.downcase(k) == name_lower, do: String.downcase(String.trim(v))
    end)
  end

  @doc """
  Finds a header value by name (case-insensitive).

  Returns the original value (not lowercased) if found, nil otherwise.
  """
  @spec find_value([{String.t(), String.t()}], String.t()) :: String.t() | nil
  def find_value(headers, target) do
    target = String.downcase(target)

    Enum.find_value(headers, fn
      {k, v} ->
        if String.downcase(k) == target, do: v, else: nil

      _ ->
        nil
    end)
  end

  @doc """
  Converts a headers list to a map with lowercased keys.
  """
  @spec to_map([{String.t(), String.t()}]) :: map()
  def to_map(headers) do
    Enum.reduce(headers, %{}, fn
      {k, v}, acc -> Map.put(acc, String.downcase(k), v)
      _, acc -> acc
    end)
  end

  @doc """
  Deduplicates headers, keeping the last occurrence of each header name.

  Comparison is case-insensitive, but the original case of the last
  occurrence is preserved.
  """
  @spec dedupe([{String.t(), String.t()}]) :: [{String.t(), String.t()}]
  def dedupe(headers) do
    headers
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      Map.put(acc, String.downcase(k), {k, v})
    end)
    |> Map.values()
  end

  @doc """
  Redacts sensitive header values for logging.

  Redacts:
  - x-api-key
  - cf-access-client-secret
  - authorization
  - proxy-authorization
  """
  @spec redact([{String.t(), String.t()}]) :: [{String.t(), String.t()}]
  def redact(headers) do
    Enum.map(headers, fn
      {name, value} ->
        lowered = String.downcase(name)

        cond do
          lowered == "x-api-key" -> {name, Env.mask_secret(value)}
          lowered == "cf-access-client-secret" -> {name, Env.mask_secret(value)}
          lowered == "authorization" -> {name, Env.mask_secret(value)}
          lowered == "proxy-authorization" -> {name, Env.mask_secret(value)}
          true -> {name, value}
        end

      other ->
        other
    end)
  end

  # Private functions

  defp ensure_read_timeout(headers, timeout_ms) do
    case get_normalized(headers, "x-stainless-read-timeout") do
      nil -> put(headers, "x-stainless-read-timeout", stainless_read_timeout(timeout_ms))
      _ -> headers
    end
  end

  defp stainless_read_timeout(timeout_ms) when is_integer(timeout_ms) do
    timeout_ms
    |> Kernel./(1000)
    |> Float.round(3)
    |> :erlang.float_to_binary(decimals: 3)
  end

  defp stainless_os do
    case :os.type() do
      {:unix, :darwin} -> "MacOS"
      {:unix, :linux} -> "Linux"
      {:unix, :freebsd} -> "FreeBSD"
      {:unix, :openbsd} -> "OpenBSD"
      {:win32, _} -> "Windows"
      _ -> "Unknown"
    end
  end

  defp stainless_arch do
    arch =
      :erlang.system_info(:system_architecture)
      |> to_string()
      |> String.downcase()

    cond do
      String.contains?(arch, "aarch64") -> "arm64"
      String.contains?(arch, "arm") -> "arm"
      String.contains?(arch, "x86_64") or String.contains?(arch, "amd64") -> "x64"
      String.contains?(arch, "i686") or String.contains?(arch, "i386") -> "x32"
      true -> "unknown"
    end
  end

  defp stainless_runtime, do: "BEAM"

  defp stainless_runtime_version do
    otp = :erlang.system_info(:otp_release) |> to_string()
    "#{System.version()} (OTP #{otp})"
  end

  defp stainless_headers(timeout_ms) do
    [
      {"x-stainless-package-version", sdk_version()},
      {"x-stainless-os", stainless_os()},
      {"x-stainless-arch", stainless_arch()},
      {"x-stainless-runtime", stainless_runtime()},
      {"x-stainless-runtime-version", stainless_runtime_version()},
      {"x-stainless-read-timeout", stainless_read_timeout(timeout_ms)}
    ]
  end

  defp sdk_version do
    Tinkex.Version.tinker_sdk()
  end

  defp user_agent do
    Application.get_env(:tinkex, :user_agent, "AsyncTinkex/Elixir #{sdk_version()}")
  end

  defp request_headers(opts) do
    []
    |> maybe_put("x-tinker-request-iteration", opts[:tinker_request_iteration])
    |> maybe_put("x-tinker-request-type", opts[:tinker_request_type])
    |> maybe_put_roundtrip(opts[:tinker_create_roundtrip_time])
  end

  defp cloudflare_headers(%{cf_access_client_id: id, cf_access_client_secret: secret}) do
    []
    |> maybe_put("CF-Access-Client-Id", id)
    |> maybe_put("CF-Access-Client-Secret", secret)
  end

  defp config_default_headers(%{default_headers: headers}) when is_map(headers) do
    Enum.map(headers, fn {k, v} -> {k, to_string(v)} end)
  end

  defp idempotency_headers(:get, _opts), do: []

  defp idempotency_headers(_method, opts) do
    key =
      case opts[:idempotency_key] do
        nil -> build_idempotency_key()
        :omit -> nil
        value -> to_string(value)
      end

    if key, do: [{"x-idempotency-key", key}], else: []
  end

  defp sampling_headers(opts) do
    if Keyword.get(opts, :sampling_backpressure, false) do
      [{"x-tinker-sampling-backpressure", "1"}]
    else
      []
    end
  end

  defp maybe_raw_response_header(opts) do
    if Keyword.get(opts, :raw_response?, false) do
      [{"x-stainless-raw-response", "raw"}]
    else
      []
    end
  end

  defp maybe_put(headers, _name, nil), do: headers
  defp maybe_put(headers, name, value), do: [{name, to_string(value)} | headers]

  defp maybe_put_roundtrip(headers, nil), do: headers

  defp maybe_put_roundtrip(headers, value) do
    [{"x-tinker-create-promise-roundtrip-time", to_string(value)} | headers]
  end

  defp build_idempotency_key do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end
end
