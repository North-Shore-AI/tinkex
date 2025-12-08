defmodule Tinkex.Telemetry.Reporter.ExceptionHandler do
  @moduledoc """
  Exception classification and cause chain traversal.

  Determines whether exceptions are user errors (4xx client errors that should
  not be retried) or unhandled exceptions (server errors, network failures, etc).

  Traverses exception cause chains to find the root cause classification.
  """

  @doc """
  Classify an exception as either a user error or unhandled exception.

  Returns:
    * `{:user_error, exception}` - if a user error is found in the exception chain
    * `:unhandled` - if no user error is found

  User errors are identified by:
    * HTTP status codes 400-499 (except 408 and 429)
    * Category field set to `:user`
    * Tinkex.Error with user_error? flag
  """
  @spec classify_exception(term()) :: {:user_error, term()} | :unhandled
  def classify_exception(%Tinkex.Error{} = error) do
    if Tinkex.Error.user_error?(error) do
      {:user_error, error}
    else
      case find_user_error_in_chain(error) do
        {:ok, user_error} -> {:user_error, user_error}
        :not_found -> :unhandled
      end
    end
  end

  def classify_exception(exception) do
    # Check the exception and its cause chain for user errors
    case find_user_error_in_chain(exception) do
      {:ok, user_error} -> {:user_error, user_error}
      :not_found -> :unhandled
    end
  end

  @doc """
  Traverse the exception cause chain to find a user error.

  Checks exception fields in order: :cause, :reason, :plug_status (4xx except 408/429),
  :__cause__, :__context__. Depth-first, first match wins.

  Uses a visited map to prevent infinite loops in circular references.

  Returns:
    * `{:ok, exception}` - if a user error is found
    * `:not_found` - if no user error is found
  """
  @spec find_user_error_in_chain(term(), map()) :: {:ok, term()} | :not_found
  def find_user_error_in_chain(exception, visited \\ %{}) do
    exception_id = :erlang.phash2(exception)

    if Map.has_key?(visited, exception_id) do
      :not_found
    else
      visited = Map.put(visited, exception_id, true)

      if user_error_exception?(exception) do
        {:ok, exception}
      else
        find_in_candidates(exception, visited)
      end
    end
  end

  # Private helpers

  defp find_in_candidates(exception, visited) do
    candidates = extract_candidates(exception)

    Enum.reduce_while(candidates, :not_found, fn candidate, _acc ->
      case find_user_error_in_chain(candidate, visited) do
        {:ok, _} = found -> {:halt, found}
        :not_found -> {:cont, :not_found}
      end
    end)
  end

  defp extract_candidates(exception) do
    []
    |> maybe_add_candidate(Map.get(exception, :cause))
    |> maybe_add_candidate(Map.get(exception, :reason))
    |> maybe_add_candidate(Map.get(exception, :__cause__))
    |> maybe_add_candidate(Map.get(exception, :__context__))
  end

  defp maybe_add_candidate(list, nil), do: list
  defp maybe_add_candidate(list, candidate) when is_map(candidate), do: list ++ [candidate]
  defp maybe_add_candidate(list, _), do: list

  defp user_error_exception?(%{status: status})
       when is_integer(status) and status in 400..499 and status not in [408, 429],
       do: true

  defp user_error_exception?(%{status_code: status})
       when is_integer(status) and status in 400..499 and status not in [408, 429],
       do: true

  defp user_error_exception?(%{plug_status: status})
       when is_integer(status) and status in 400..499 and status not in [408, 429],
       do: true

  defp user_error_exception?(%{category: :user}), do: true
  defp user_error_exception?(_), do: false
end
