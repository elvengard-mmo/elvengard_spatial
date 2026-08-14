defmodule ElvenGard.Spatial.Grid2D do
  @moduledoc """
  Immutable uniform-grid broad-phase index for two-dimensional worlds.

  An entity may occupy more than one cell. Queries first collect identifiers
  from the overlapping cells, then discard entries whose axis-aligned bounds do
  not intersect the query bounds. Returned identifiers are sorted using Erlang
  term ordering so results remain deterministic across runs.

  The grid intentionally returns broad-phase candidates. Circle and swept-circle
  queries use their enclosing AABB and may therefore contain false positives;
  callers remain responsible for exact collision tests.
  """

  alias ElvenGard.Spatial.AABB
  alias ElvenGard.Spatial.Grid2D.Entry

  @enforce_keys [:cell_size]
  defstruct cell_size: nil, cells: %{}, entries: %{}

  @type id :: any()
  @type layer :: atom()
  @type cell :: {integer(), integer()}
  @type put_entry :: {id(), AABB.t(), layer() | [layer()]}
  @type t :: %__MODULE__{
          cell_size: number(),
          cells: %{optional(cell()) => MapSet.t(id())},
          entries: %{optional(id()) => Entry.t()}
        }

  ## Public API

  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    cell_size = Keyword.get(opts, :cell_size, 128)

    unless is_number(cell_size) and cell_size > 0 do
      raise ArgumentError, ":cell_size must be a positive number"
    end

    %__MODULE__{cell_size: cell_size}
  end

  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{entries: entries}), do: map_size(entries)

  @spec ids(t(), Keyword.t()) :: [id()]
  def ids(%__MODULE__{entries: entries}, opts \\ []) do
    layers = opts |> Keyword.get(:layers, []) |> normalize_layers()

    entries
    |> Enum.filter(fn {_id, entry} -> matches_layers?(entry.layers, layers) end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort()
  end

  @spec fetch(t(), id()) :: {:ok, AABB.t()} | :error
  def fetch(%__MODULE__{entries: entries}, id) do
    case Map.fetch(entries, id) do
      {:ok, entry} -> {:ok, entry.bounds}
      :error -> :error
    end
  end

  @spec put(t(), id(), AABB.t(), Keyword.t()) :: t()
  def put(%__MODULE__{} = grid, id, %AABB{} = bounds, opts \\ []) do
    layers = opts |> Keyword.get(:layers, []) |> normalize_layers()

    case Map.get(grid.entries, id) do
      %Entry{bounds: ^bounds, layers: ^layers} ->
        grid

      _entry ->
        replace_entry(grid, id, bounds, layers)
    end
  end

  @spec put_many(t(), [put_entry()]) :: t()
  def put_many(%__MODULE__{} = grid, entries) when is_list(entries) do
    Enum.reduce(entries, grid, fn {id, bounds, layers}, index ->
      put(index, id, bounds, layers: layers)
    end)
  end

  @spec delete(t(), id()) :: t()
  def delete(%__MODULE__{} = grid, id) do
    case Map.pop(grid.entries, id) do
      {nil, _entries} ->
        grid

      {%Entry{cells: cells_for_entry}, entries} ->
        cells = Enum.reduce(cells_for_entry, grid.cells, &delete_from_cell(&2, &1, id))
        %{grid | cells: cells, entries: entries}
    end
  end

  @spec query_aabb(t(), AABB.t(), Keyword.t()) :: [id()]
  def query_aabb(%__MODULE__{} = grid, %AABB{} = bounds, opts \\ []) do
    layers = opts |> Keyword.get(:layers, []) |> normalize_layers()

    grid
    |> candidate_ids(bounds)
    |> Enum.filter(fn id ->
      entry = Map.fetch!(grid.entries, id)
      AABB.intersects?(entry.bounds, bounds) and matches_layers?(entry.layers, layers)
    end)
    |> Enum.sort()
  end

  @spec query_circle(t(), {number(), number()}, non_neg_integer() | float(), Keyword.t()) ::
          [id()]
  def query_circle(%__MODULE__{} = grid, {x, y}, radius, opts \\ []) do
    query_aabb(grid, AABB.from_circle(x, y, radius), opts)
  end

  @spec query_swept_circle(
          t(),
          {number(), number()},
          {number(), number()},
          non_neg_integer() | float(),
          Keyword.t()
        ) :: [id()]
  def query_swept_circle(%__MODULE__{} = grid, origin, destination, radius, opts \\ []) do
    query_aabb(grid, AABB.swept_circle(origin, destination, radius), opts)
  end

  ## Private functions

  defp occupied_cells(%__MODULE__{cell_size: cell_size}, %AABB{} = bounds) do
    min_x = floor(bounds.min_x / cell_size)
    max_x = floor(bounds.max_x / cell_size)
    min_y = floor(bounds.min_y / cell_size)
    max_y = floor(bounds.max_y / cell_size)

    for cell_x <- min_x..max_x, cell_y <- min_y..max_y, do: {cell_x, cell_y}
  end

  defp candidate_ids(grid, bounds) do
    grid
    |> occupied_cells(bounds)
    |> Enum.reduce(MapSet.new(), fn cell, candidates ->
      case Map.fetch(grid.cells, cell) do
        {:ok, ids} -> MapSet.union(candidates, ids)
        :error -> candidates
      end
    end)
  end

  defp replace_entry(grid, id, bounds, layers) do
    cells_for_entry = occupied_cells(grid, bounds)
    grid = delete(grid, id)

    cells =
      Enum.reduce(cells_for_entry, grid.cells, fn cell, cells ->
        Map.update(cells, cell, MapSet.new([id]), &MapSet.put(&1, id))
      end)

    entry = %Entry{bounds: bounds, layers: layers, cells: cells_for_entry}
    %{grid | cells: cells, entries: Map.put(grid.entries, id, entry)}
  end

  defp delete_from_cell(cells, cell, id) do
    remaining = cells |> Map.fetch!(cell) |> MapSet.delete(id)

    case MapSet.size(remaining) do
      0 -> Map.delete(cells, cell)
      _size -> Map.put(cells, cell, remaining)
    end
  end

  defp normalize_layers(layer) when is_atom(layer), do: MapSet.new([layer])
  defp normalize_layers(layers) when is_list(layers), do: MapSet.new(layers)

  defp matches_layers?(entry_layers, query_layers) do
    MapSet.size(query_layers) == 0 or not MapSet.disjoint?(entry_layers, query_layers)
  end
end
