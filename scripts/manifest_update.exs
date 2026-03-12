defmodule ManifestUpdate do
  @manifest_path "lib/tinkex/manifest.yaml"
  @types_glob "lib/tinkex/types/**/*.ex"

  def run do
    manifest = Jason.decode!(File.read!(@manifest_path))
    types = build_types()

    manifest =
      manifest
      |> Map.put("types", Map.merge(types, manual_types()))
      |> Map.put("retry_policies", retry_policies())
      |> update_endpoints()

    File.write!(@manifest_path, Jason.encode!(manifest, pretty: true))
  end

  defp build_types do
    @types_glob
    |> Path.wildcard()
    |> Enum.flat_map(&modules_from_file/1)
    |> Enum.reduce(%{}, fn {type_name, defstruct_fields, enforce_keys}, acc ->
      Map.put(acc, type_name, build_type_def(defstruct_fields, enforce_keys))
    end)
  end

  defp modules_from_file(file) do
    {:ok, ast} = Code.string_to_quoted(File.read!(file))

    {_, modules} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _, [alias_ast, [do: block]]} = node, acc ->
          module_name = Macro.to_string(alias_ast)
          {defstruct_fields, enforce_keys} = extract_module_info(block)
          type_name = type_name_from_module(module_name)
          {node, [{type_name, defstruct_fields, enforce_keys} | acc]}

        node, acc ->
          {node, acc}
      end)

    modules
  end

  defp extract_module_info(block) do
    {_, acc} =
      Macro.prewalk(block, %{defstruct: nil, enforce: []}, fn
        {:defstruct, _, [fields]} = node, acc ->
          {node, %{acc | defstruct: fields}}

        {:@, _, [{:enforce_keys, _, [keys]}]} = node, acc ->
          {node, %{acc | enforce: keys}}

        node, acc ->
          {node, acc}
      end)

    {acc.defstruct, acc.enforce}
  end

  defp build_type_def(nil, _enforce_keys), do: %{"type" => "any"}

  defp build_type_def(fields, enforce_keys) do
    field_names =
      Enum.map(fields, fn
        {name, _default} -> name
        name -> name
      end)

    fields_map =
      Enum.reduce(field_names, %{}, fn name, acc ->
        Map.put(acc, Atom.to_string(name), %{
          "type" => "any",
          "required" => name in enforce_keys
        })
      end)

    %{"type" => "object", "fields" => fields_map}
  end

  defp type_name_from_module(module_name) do
    base = String.replace_prefix(module_name, "Tinkex.Types.", "")

    if String.starts_with?(base, "Telemetry.") do
      suffix = String.replace_prefix(base, "Telemetry.", "")

      if String.starts_with?(suffix, "Telemetry") do
        suffix
      else
        "Telemetry" <> suffix
      end
    else
      base
      |> String.split(".")
      |> List.last()
    end
  end

  defp manual_types do
    %{
      "WeightsInfoRequest" => %{
        "type" => "object",
        "fields" => %{
          "tinker_path" => %{"type" => "string", "required" => true}
        }
      },
      "GenericMap" => %{"type" => "map"}
    }
  end

  defp retry_policies do
    %{"no_retry" => %{"max_retries" => 0}}
  end

  defp update_endpoints(%{"endpoints" => endpoints} = manifest) do
    updated = Enum.map(endpoints, &update_endpoint/1)
    Map.put(manifest, "endpoints", updated)
  end

  defp update_endpoints(manifest), do: manifest

  defp update_endpoint(endpoint) do
    id = endpoint["id"]

    endpoint
    |> apply_request_response(id)
    |> apply_resource(id)
    |> apply_async(id)
    |> apply_retry(id)
    |> apply_timeout(id)
    |> apply_transform(id)
    |> apply_body_type()
  end

  defp apply_request_response(endpoint, id) do
    case Map.get(endpoint_type_map(), id) do
      nil ->
        endpoint

      %{"request" => request, "response" => response} ->
        endpoint
        |> Map.put("request", request)
        |> Map.put("response", response)

      %{"request" => request} ->
        Map.put(endpoint, "request", request)

      %{"response" => response} ->
        Map.put(endpoint, "response", response)
    end
  end

  defp apply_resource(endpoint, id) do
    case Map.get(resource_overrides(), id) do
      nil -> endpoint
      resource -> Map.put(endpoint, "resource", resource)
    end
  end

  defp apply_async(endpoint, id) do
    if MapSet.member?(async_endpoints(), id) do
      endpoint
      |> Map.put("async", true)
      |> Map.put("poll_endpoint", "retrieve_future")
    else
      endpoint
      |> Map.delete("async")
      |> Map.delete("poll_endpoint")
    end
  end

  defp apply_retry(endpoint, id) do
    if MapSet.member?(no_retry_endpoints(), id) do
      Map.put(endpoint, "retry", "no_retry")
    else
      Map.delete(endpoint, "retry")
    end
  end

  defp apply_timeout(endpoint, id) do
    case Map.get(timeout_overrides(), id) do
      nil -> endpoint
      timeout -> Map.put(endpoint, "timeout", timeout)
    end
  end

  defp apply_transform(endpoint, id) do
    if MapSet.member?(transform_endpoints(), id) do
      Map.put(endpoint, "transform", %{"drop_nil?" => true})
    else
      Map.delete(endpoint, "transform")
    end
  end

  defp apply_body_type(endpoint) do
    method = String.upcase(to_string(endpoint["method"]))

    if endpoint["body_type"] == nil and method in ["GET", "DELETE", "HEAD", "OPTIONS"] do
      Map.put(endpoint, "body_type", "raw")
    else
      endpoint
    end
  end

  defp endpoint_type_map do
    %{
      "create_session" => %{
        "request" => "CreateSessionRequest",
        "response" => "CreateSessionResponse"
      },
      "session_heartbeat" => %{
        "request" => "SessionHeartbeatRequest",
        "response" => "SessionHeartbeatResponse"
      },
      "create_sampling_session" => %{
        "request" => "CreateSamplingSessionRequest",
        "response" => "CreateSamplingSessionResponse"
      },
      "get_server_capabilities" => %{"response" => "GetServerCapabilitiesResponse"},
      "healthz" => %{"response" => "HealthResponse"},
      "create_model" => %{"request" => "CreateModelRequest", "response" => "CreateModelResponse"},
      "get_info" => %{"request" => "GetInfoRequest", "response" => "GetInfoResponse"},
      "unload_model" => %{"request" => "UnloadModelRequest", "response" => "GenericMap"},
      "load_weights" => %{"request" => "LoadWeightsRequest", "response" => "GenericMap"},
      "save_weights" => %{"request" => "SaveWeightsRequest", "response" => "GenericMap"},
      "save_weights_for_sampler" => %{
        "request" => "SaveWeightsForSamplerRequest",
        "response" => "GenericMap"
      },
      "weights_info" => %{"request" => "WeightsInfoRequest", "response" => "WeightsInfoResponse"},
      "retrieve_future" => %{
        "request" => "FutureRetrieveRequest",
        "response" => "FutureRetrieveResponse"
      },
      "forward" => %{"request" => "ForwardRequest", "response" => "GenericMap"},
      "forward_backward" => %{"request" => "ForwardBackwardRequest", "response" => "GenericMap"},
      "optim_step" => %{"request" => "OptimStepRequest", "response" => "GenericMap"},
      "asample" => %{"request" => "SampleRequest", "response" => "SampleResponse"},
      "stream_sample" => %{"request" => "SampleRequest"},
      "telemetry" => %{"request" => "TelemetrySendRequest", "response" => "TelemetryResponse"},
      "get_session" => %{"response" => "GetSessionResponse"},
      "list_sessions" => %{"response" => "ListSessionsResponse"},
      "list_checkpoints" => %{"response" => "CheckpointsListResponse"},
      "list_user_checkpoints" => %{"response" => "CheckpointsListResponse"},
      "get_checkpoint_archive_url" => %{"response" => "CheckpointArchiveUrlResponse"},
      "delete_checkpoint" => %{"response" => "GenericMap"},
      "publish_checkpoint" => %{"response" => "GenericMap"},
      "unpublish_checkpoint" => %{"response" => "GenericMap"},
      "get_sampler" => %{"response" => "GetSamplerResponse"},
      "get_training_run" => %{"response" => "TrainingRun"},
      "list_training_runs" => %{"response" => "TrainingRunsResponse"},
      "meta" => %{"response" => "GenericMap"}
    }
  end

  defp resource_overrides do
    %{
      "create_session" => "session",
      "session_heartbeat" => "session",
      "heartbeat" => "session",
      "create_sampling_session" => "session",
      "get_server_capabilities" => "session",
      "healthz" => "session",
      "create_model" => "session",
      "get_info" => "training",
      "unload_model" => "training",
      "load_weights" => "training",
      "save_weights" => "training",
      "save_weights_for_sampler" => "training",
      "weights_info" => "training",
      "retrieve_future" => "futures",
      "forward" => "training",
      "forward_backward" => "training",
      "optim_step" => "training",
      "asample" => "sampling",
      "stream_sample" => "sampling",
      "telemetry" => "telemetry",
      "get_session" => "training",
      "list_sessions" => "training",
      "list_checkpoints" => "training",
      "list_user_checkpoints" => "training",
      "get_checkpoint_archive_url" => "training",
      "delete_checkpoint" => "training",
      "publish_checkpoint" => "training",
      "unpublish_checkpoint" => "training",
      "get_sampler" => "sampling",
      "get_training_run" => "training",
      "list_training_runs" => "training",
      "meta" => "training",
      "events" => "telemetry"
    }
  end

  defp async_endpoints do
    MapSet.new([
      "forward",
      "forward_backward",
      "optim_step",
      "unload_model",
      "load_weights",
      "save_weights",
      "save_weights_for_sampler"
    ])
  end

  defp no_retry_endpoints do
    MapSet.new(["asample", "session_heartbeat"])
  end

  defp timeout_overrides do
    %{"session_heartbeat" => 10_000}
  end

  defp transform_endpoints do
    MapSet.new(["asample", "stream_sample", "forward", "forward_backward", "optim_step"])
  end
end

ManifestUpdate.run()
