defmodule Tinkex.CLI.Pagination do
  @moduledoc """
  Pagination logic for listing checkpoints and training runs.
  """

  @doc """
  Paginates through results using a fetch function.
  """
  def paginate_with(
        _fetch_fun,
        acc,
        _offset,
        _page_size,
        target,
        total_count,
        initial_offset,
        label
      )
      when target != :all and length(acc) >= target do
    progress_total = progress_total(target, total_count, initial_offset)
    maybe_log_progress(label, min(length(acc), target), progress_total)

    final_total =
      total_count || (progress_total && progress_total + initial_offset) ||
        length(acc) + initial_offset

    {:ok, %{items: Enum.take(acc, target), total: final_total}}
  end

  def paginate_with(
        fetch_fun,
        acc,
        offset,
        page_size,
        target,
        total_count,
        initial_offset,
        label
      ) do
    progress_total = progress_total(target, total_count, initial_offset)
    maybe_log_progress(label, length(acc), progress_total)
    request_limit = requested_limit(page_size, target, length(acc))

    case fetch_fun.(request_limit, offset) do
      {:ok, {items, cursor}} ->
        ctx = %{
          fetch_fun: fetch_fun,
          acc: acc,
          offset: offset,
          page_size: page_size,
          target: target,
          total_count: total_count,
          initial_offset: initial_offset,
          label: label
        }

        handle_page_result(ctx, items, cursor)

      {:error, _} = error ->
        error
    end
  end

  defp handle_page_result(ctx, items, cursor) do
    new_total = ctx.total_count || cursor_total(cursor)
    new_target = update_target(ctx.target, new_total, ctx.initial_offset)
    new_acc = ctx.acc ++ items
    new_offset = ctx.offset + length(items)

    page_state = %{
      new_acc: new_acc,
      new_target: new_target,
      new_total: new_total,
      new_offset: new_offset,
      initial_offset: ctx.initial_offset,
      items_count: length(items),
      request_limit: requested_limit(ctx.page_size, ctx.target, length(ctx.acc))
    }

    case determine_pagination_action(page_state) do
      {:target_reached, final_total} ->
        log_and_return_target_reached(ctx.label, page_state, final_total)

      {:all_exhausted_no_total, final_total} ->
        log_and_return_complete(ctx.label, page_state, final_total)

      {:all_complete, final_total} ->
        log_and_return_complete(ctx.label, page_state, final_total)

      :continue ->
        paginate_with(
          ctx.fetch_fun,
          new_acc,
          new_offset,
          ctx.page_size,
          new_target,
          new_total,
          ctx.initial_offset,
          ctx.label
        )
    end
  end

  defp determine_pagination_action(page_state) do
    %{
      new_acc: new_acc,
      new_target: new_target,
      new_total: new_total,
      new_offset: new_offset,
      initial_offset: initial_offset,
      items_count: items_count,
      request_limit: request_limit
    } = page_state

    progress = progress_total(new_target, new_total, initial_offset)

    cond do
      target_reached?(new_target, new_acc) ->
        {:target_reached, new_total || new_target + initial_offset}

      all_exhausted_no_total?(new_target, items_count, request_limit, new_total) ->
        {:all_exhausted_no_total, new_offset}

      all_complete?(new_target, progress, new_acc) ->
        {:all_complete, new_total || length(new_acc) + initial_offset}

      true ->
        :continue
    end
  end

  defp target_reached?(target, acc) when target != :all, do: length(acc) >= target
  defp target_reached?(_target, _acc), do: false

  defp all_exhausted_no_total?(:all, items_count, request_limit, total),
    do: items_count < request_limit and is_nil(total)

  defp all_exhausted_no_total?(_target, _items_count, _request_limit, _total), do: false

  defp all_complete?(:all, progress, acc) when is_integer(progress), do: length(acc) >= progress
  defp all_complete?(_target, _progress, _acc), do: false

  defp log_and_return_target_reached(label, page_state, final_total) do
    %{
      new_acc: new_acc,
      new_target: new_target,
      new_total: new_total,
      initial_offset: initial_offset
    } =
      page_state

    maybe_log_progress(
      label,
      min(length(new_acc), new_target),
      progress_total(new_target, new_total, initial_offset)
    )

    {:ok, %{items: Enum.take(new_acc, new_target), total: final_total}}
  end

  defp log_and_return_complete(label, page_state, final_total) do
    %{
      new_acc: new_acc,
      new_target: new_target,
      new_total: new_total,
      initial_offset: initial_offset
    } =
      page_state

    maybe_log_progress(
      label,
      length(new_acc),
      progress_total(new_target, new_total, initial_offset)
    )

    {:ok, %{items: new_acc, total: final_total}}
  end

  @doc """
  Determines the initial page limit based on the requested limit and page size.
  """
  def initial_page_limit(limit, page_size) when is_integer(limit) and limit > 0,
    do: min(limit, page_size)

  def initial_page_limit(_limit, page_size), do: page_size

  @doc """
  Calculates the pagination target based on limit, total count, and offset.
  """
  def pagination_target(limit, total_count, offset) do
    available = if is_integer(total_count), do: max(total_count - offset, 0), else: nil

    cond do
      limit == 0 and is_integer(available) -> available
      limit == 0 -> :all
      is_integer(available) -> min(limit, available)
      true -> limit
    end
  end

  @doc """
  Extracts the total count from a cursor.
  """
  def cursor_total(%Tinkex.Types.Cursor{total_count: total}), do: total
  def cursor_total(%{total_count: total}) when is_integer(total), do: total
  def cursor_total(map) when is_map(map), do: map["total_count"] || map[:total_count]
  def cursor_total(_), do: nil

  # Private functions

  defp progress_total(target, _total_count, _initial_offset) when is_integer(target), do: target

  defp progress_total(:all, total_count, initial_offset) when is_integer(total_count),
    do: max(total_count - initial_offset, 0)

  defp progress_total(_target, _total_count, _initial_offset), do: nil

  defp requested_limit(page_size, :all, _current), do: page_size

  defp requested_limit(page_size, target, current) when is_integer(target) do
    remaining = max(target - current, 0)
    min(page_size, remaining)
  end

  defp update_target(:all, total_count, initial_offset) when is_integer(total_count),
    do: max(total_count - initial_offset, 0)

  defp update_target(target, _total_count, _initial_offset), do: target

  defp maybe_log_progress(_label, _current, nil), do: :ok

  defp maybe_log_progress(label, current, total) do
    if is_integer(total) do
      IO.puts(:stderr, "Fetching #{label}: #{current}/#{total}")
    else
      IO.puts(:stderr, "Fetching #{label}: #{current}")
    end
  end
end
