defmodule Tinkex.CLI.Commands.Run do
  @moduledoc """
  Training run management commands: list and info.
  """

  alias Tinkex.Error
  alias Tinkex.Types.{TrainingRun, TrainingRunsResponse}

  @doc """
  Manages training run operations (list, info).
  """
  @spec run_run_management(atom(), map(), map()) :: {:ok, map()} | {:error, term()}
  def run_run_management(action, options, overrides \\ %{}) do
    deps = management_deps(overrides)

    with {:ok, config} <- build_config(options, deps) do
      case action do
        :list -> run_list(config, options, deps)
        :info -> run_info(config, options, deps)
      end
    end
  end

  defp management_deps(overrides) do
    env_overrides = Application.get_env(:tinkex, :cli_management_deps, %{}) || %{}

    %{
      rest_api_module: Tinkex.API.Rest,
      rest_client_module: Tinkex.RestClient,
      checkpoint_download_module: Tinkex.CheckpointDownload,
      config_module: Tinkex.Config,
      json_module: Jason,
      checkpoint_page_size: 1000,
      run_page_size: 100
    }
    |> Map.merge(env_overrides)
    |> Map.merge(overrides)
  end

  defp build_config(options, %{config_module: config_module}) do
    http_pool =
      options
      |> Map.get(:http_pool)
      |> normalize_http_pool()

    config_opts =
      options
      |> Map.take([:api_key, :base_url, :timeout])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Keyword.new()
      |> maybe_put_http_pool(http_pool)

    {:ok, config_module.new(config_opts)}
  rescue
    e in ArgumentError ->
      {:error, Error.new(:validation, Exception.message(e), category: :user)}
  end

  defp normalize_http_pool(nil), do: nil
  defp normalize_http_pool(pool) when is_atom(pool), do: pool

  defp normalize_http_pool(pool) when is_binary(pool) and byte_size(pool) > 0 do
    String.to_atom(pool)
  end

  defp normalize_http_pool(pool) when is_binary(pool), do: nil

  defp normalize_http_pool(other),
    do: raise(ArgumentError, "http_pool must be a string or atom, got: #{inspect(other)}")

  defp maybe_put_http_pool(keyword, nil), do: keyword
  defp maybe_put_http_pool(keyword, pool), do: Keyword.put(keyword, :http_pool, pool)

  defp run_list(config, options, deps) do
    limit = options |> Map.get(:limit, 20) |> max(0)
    offset = max(Map.get(options, :offset, 0), 0)
    page_size = Map.get(deps, :run_page_size, 100)

    with {:ok, format} <- management_format(options),
         {:ok, resp} <-
           normalize_run_response(
             deps.rest_api_module.list_training_runs(
               config,
               Tinkex.CLI.Pagination.initial_page_limit(limit, page_size),
               offset
             )
           ),
         {:ok, %{items: runs, total: total}} <-
           Tinkex.CLI.Pagination.paginate_with(
             fn req_limit, req_offset ->
               case normalize_run_response(
                      deps.rest_api_module.list_training_runs(config, req_limit, req_offset)
                    ) do
                 {:ok, %TrainingRunsResponse{} = response} ->
                   {:ok, {response.training_runs, response.cursor}}

                 {:error, _} = error ->
                   error
               end
             end,
             resp.training_runs,
             offset + length(resp.training_runs),
             page_size,
             Tinkex.CLI.Pagination.pagination_target(
               limit,
               Tinkex.CLI.Pagination.cursor_total(resp.cursor),
               offset
             ),
             Tinkex.CLI.Pagination.cursor_total(resp.cursor),
             offset,
             "training runs"
           ) do
      render_run_list(
        %{
          runs: runs,
          total:
            total || Tinkex.CLI.Pagination.cursor_total(resp.cursor) || offset + length(runs),
          shown: length(runs)
        },
        format,
        deps
      )
    else
      {:error, %Error{} = error} ->
        IO.puts(:stderr, "Run list failed: #{Error.format(error)}")
        {:error, error}
    end
  end

  defp run_info(config, options, deps) do
    run_id = Map.fetch!(options, :run_id)

    with {:ok, format} <- management_format(options),
         {:ok, run} <- fetch_run(config, run_id, deps) do
      render_run_info(run, format, deps)
    else
      {:error, %Error{} = error} ->
        IO.puts(:stderr, "Run info failed: #{Error.format(error)}")
        {:error, error}
    end
  end

  defp fetch_run(config, run_id, deps) do
    case deps.rest_api_module.get_training_run(config, run_id) do
      {:ok, %TrainingRun{} = run} ->
        {:ok, run}

      {:ok, data} when is_map(data) ->
        {:ok, TrainingRun.from_map(data)}

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  defp render_run_list(%{runs: runs, total: total, shown: shown}, format, deps) do
    alias Tinkex.CLI.Formatting

    case format do
      :json ->
        payload = %{
          "runs" => Enum.map(runs, &Formatting.run_to_map/1),
          "total" => total,
          "shown" => shown
        }

        IO.puts(deps.json_module.encode!(payload))

      :table ->
        IO.puts("Training runs (#{shown}/#{total})")
        IO.puts("Run ID\tBase Model\tOwner\tLoRA\tStatus\tLast Update")

        Enum.each(runs, fn run ->
          map = Formatting.run_to_map(run)

          IO.puts(
            Enum.join(
              [
                map["training_run_id"],
                map["base_model"],
                map["model_owner"],
                Formatting.format_lora(map),
                Formatting.format_status(map),
                Formatting.format_datetime(map["last_request_time"])
              ],
              "\t"
            )
          )
        end)
    end

    {:ok, %{command: :run, action: :list, count: shown, total: total}}
  end

  defp render_run_info(run, format, deps) do
    alias Tinkex.CLI.Formatting

    map = Formatting.run_to_map(run)

    case format do
      :json ->
        IO.puts(deps.json_module.encode!(map))

      :table ->
        IO.puts("#{map["training_run_id"]} (#{map["base_model"]})")
        IO.puts("Owner: #{map["model_owner"]}")
        IO.puts("LoRA: #{if(map["is_lora"], do: "Yes", else: "No")}")
        if map["lora_rank"], do: IO.puts("LoRA rank: #{map["lora_rank"]}")
        IO.puts("Status: #{Formatting.format_status(map)}")
        IO.puts("Last update: #{Formatting.format_datetime(map["last_request_time"])}")

        if map["last_checkpoint"] do
          IO.puts("Last training checkpoint: #{map["last_checkpoint"]["checkpoint_id"]}")
          IO.puts("  Time: #{Formatting.format_datetime(map["last_checkpoint"]["time"])}")
          IO.puts("  Path: #{map["last_checkpoint"]["tinker_path"]}")
        end

        if map["last_sampler_checkpoint"] do
          IO.puts("Last sampler checkpoint: #{map["last_sampler_checkpoint"]["checkpoint_id"]}")
          IO.puts("  Time: #{Formatting.format_datetime(map["last_sampler_checkpoint"]["time"])}")
          IO.puts("  Path: #{map["last_sampler_checkpoint"]["tinker_path"]}")
        end

        if map["user_metadata"] do
          IO.puts(
            "Metadata: " <>
              Enum.map_join(map["user_metadata"], ", ", fn {k, v} -> "#{k}=#{v}" end)
          )
        end
    end

    {:ok, %{command: :run, action: :info, run_id: map["training_run_id"]}}
  end

  defp management_format(options) do
    format =
      cond do
        Map.get(options, :json, false) -> "json"
        is_binary(Map.get(options, :format)) -> String.downcase(Map.get(options, :format))
        Map.get(options, :format) == :json -> "json"
        Map.get(options, :format) == :table -> "table"
        true -> "table"
      end

    case format do
      "json" -> {:ok, :json}
      "table" -> {:ok, :table}
      other -> {:error, Error.new(:validation, "Invalid format: #{other}", category: :user)}
    end
  end

  defp normalize_run_response({:ok, %TrainingRunsResponse{} = resp}), do: {:ok, resp}

  defp normalize_run_response({:ok, data}) when is_map(data) do
    {:ok, TrainingRunsResponse.from_map(data)}
  end

  defp normalize_run_response({:error, _} = error), do: error
end
