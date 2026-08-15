defmodule ElvenGard.Spatial.InterestGraph do
  @moduledoc """
  Immutable incremental area-of-interest graph backed by uniform grids.

  Entities and observers both have axis-aligned bounds. The graph maintains
  the two inverse edge sets needed by replication: visible entities for each
  observer and recipients for each entity. Moving one item only recomputes
  edges touching that item; it never rebuilds every observer view.

  Observer layer filters are optional. An observer without filters sees every
  intersecting entity. Bounds are exact after the grid broad phase, including
  entities crossing cell boundaries.
  """

  alias ElvenGard.Spatial.InterestGraph.Delta
  alias ElvenGard.Spatial.{AABB, Grid2D}

  @enforce_keys [:entity_grid, :observer_grid]
  defstruct entity_grid: nil,
            observer_grid: nil,
            entity_layers: %{},
            observer_layers: %{},
            subscriptions: %{},
            recipients: %{}

  @type id :: any()
  @type layer :: Grid2D.layer()
  @type entry :: {id(), AABB.t(), layer() | [layer()]}
  @type t :: %__MODULE__{
          entity_grid: Grid2D.t(),
          observer_grid: Grid2D.t(),
          entity_layers: %{optional(id()) => MapSet.t(layer())},
          observer_layers: %{optional(id()) => MapSet.t(layer())},
          subscriptions: %{optional(id()) => MapSet.t(id())},
          recipients: %{optional(id()) => MapSet.t(id())}
        }

  ## Public API

  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    cell_size = Keyword.get(opts, :cell_size, 128)

    %__MODULE__{
      entity_grid: Grid2D.new(cell_size: cell_size),
      observer_grid: Grid2D.new(cell_size: cell_size)
    }
  end

  @spec put_entity(t(), id(), AABB.t(), Keyword.t()) :: {t(), Delta.t()}
  def put_entity(%__MODULE__{} = graph, id, %AABB{} = bounds, opts \\ []) do
    layers = opts |> Keyword.get(:layers, []) |> normalize_layers()
    {graph, previous, current} = put_entity_state(graph, id, bounds, layers)
    {graph, Delta.new(previous, current)}
  end

  @spec put_entities(t(), [entry()]) :: {t(), %{optional(id()) => Delta.t()}}
  def put_entities(%__MODULE__{} = graph, entries) when is_list(entries) do
    Enum.reduce(entries, {graph, %{}}, fn {id, bounds, layers}, {graph, deltas} ->
      {graph, delta} = put_entity(graph, id, bounds, layers: layers)
      {graph, Map.put(deltas, id, delta)}
    end)
  end

  @spec apply_entity_changes(t(), [entry()], [id()]) ::
          {t(), %{optional(id()) => Delta.t()}}
  def apply_entity_changes(%__MODULE__{} = graph, put_entries, deleted_ids)
      when is_list(put_entries) and is_list(deleted_ids) do
    touched_ids =
      put_entries
      |> Enum.map(&elem(&1, 0))
      |> Kernel.++(deleted_ids)
      |> Enum.uniq()

    previous = Map.new(touched_ids, &{&1, recipient_set(graph, &1)})

    graph =
      deleted_ids
      |> Enum.reduce(graph, fn id, graph -> elem(delete_entity(graph, id), 0) end)
      |> then(fn graph -> elem(put_entities(graph, put_entries), 0) end)

    deltas =
      Map.new(touched_ids, fn id ->
        {id, Delta.new(Map.fetch!(previous, id), recipient_set(graph, id))}
      end)

    {graph, deltas}
  end

  @spec update_entities(t(), [entry()], [id()]) :: t()
  def update_entities(%__MODULE__{} = graph, put_entries, deleted_ids)
      when is_list(put_entries) and is_list(deleted_ids) do
    graph =
      Enum.reduce(deleted_ids, graph, fn id, graph ->
        elem(delete_entity_state(graph, id), 0)
      end)

    Enum.reduce(put_entries, graph, fn {id, bounds, layers}, graph ->
      layers = normalize_layers(layers)
      graph |> put_entity_state(id, bounds, layers) |> elem(0)
    end)
  end

  @spec replace_entities(t(), [entry()]) :: t()
  def replace_entities(%__MODULE__{} = graph, entries) when is_list(entries) do
    observers =
      Enum.map(graph.observer_layers, fn {observer_id, layers} ->
        {:ok, bounds} = Grid2D.fetch(graph.observer_grid, observer_id)
        {observer_id, bounds, MapSet.to_list(layers)}
      end)

    graph = new(cell_size: graph.entity_grid.cell_size)
    {graph, _entity_deltas} = put_entities(graph, entries)
    {graph, _observer_deltas} = put_observers(graph, observers)
    graph
  end

  @spec delete_entity(t(), id()) :: {t(), Delta.t()}
  def delete_entity(%__MODULE__{} = graph, id) do
    {graph, previous} = delete_entity_state(graph, id)
    {graph, Delta.new(previous, MapSet.new())}
  end

  @spec put_observer(t(), id(), AABB.t(), Keyword.t()) :: {t(), Delta.t()}
  def put_observer(%__MODULE__{} = graph, id, %AABB{} = bounds, opts \\ []) do
    layers = opts |> Keyword.get(:layers, []) |> normalize_layers()
    {graph, previous, current} = put_observer_state(graph, id, bounds, layers)
    {graph, Delta.new(previous, current)}
  end

  @spec put_observers(t(), [entry()]) :: {t(), %{optional(id()) => Delta.t()}}
  def put_observers(%__MODULE__{} = graph, entries) when is_list(entries) do
    Enum.reduce(entries, {graph, %{}}, fn {id, bounds, layers}, {graph, deltas} ->
      {graph, delta} = put_observer(graph, id, bounds, layers: layers)
      {graph, Map.put(deltas, id, delta)}
    end)
  end

  @spec sync_observers(t(), [entry()]) :: {t(), %{optional(id()) => Delta.t()}}
  def sync_observers(%__MODULE__{} = graph, entries) when is_list(entries) do
    desired_ids = entries |> MapSet.new(&elem(&1, 0))
    previous_ids = graph.observer_layers |> Map.keys() |> MapSet.new()
    deleted_ids = MapSet.difference(previous_ids, desired_ids)
    touched_ids = MapSet.union(previous_ids, desired_ids)
    previous = Map.new(touched_ids, &{&1, subscription_set(graph, &1)})

    graph =
      deleted_ids
      |> Enum.reduce(graph, fn id, graph -> elem(delete_observer(graph, id), 0) end)
      |> then(fn graph -> elem(put_observers(graph, entries), 0) end)

    deltas =
      Map.new(touched_ids, fn id ->
        {id, Delta.new(Map.fetch!(previous, id), subscription_set(graph, id))}
      end)

    {graph, deltas}
  end

  @spec sync_observer_views(t(), [entry()]) :: {t(), %{optional(id()) => MapSet.t(id())}}
  def sync_observer_views(%__MODULE__{} = graph, entries) when is_list(entries) do
    desired_ids = entries |> MapSet.new(&elem(&1, 0))
    previous_ids = graph.observer_layers |> Map.keys() |> MapSet.new()

    graph =
      previous_ids
      |> MapSet.difference(desired_ids)
      |> Enum.reduce(graph, fn id, graph -> elem(delete_observer_state(graph, id), 0) end)

    graph =
      Enum.reduce(entries, graph, fn {id, bounds, layers}, graph ->
        layers = normalize_layers(layers)
        graph |> put_observer_state(id, bounds, layers) |> elem(0)
      end)

    views = Map.new(desired_ids, &{&1, subscription_set(graph, &1)})
    {graph, views}
  end

  @spec delete_observer(t(), id()) :: {t(), Delta.t()}
  def delete_observer(%__MODULE__{} = graph, id) do
    {graph, previous} = delete_observer_state(graph, id)
    {graph, Delta.new(previous, MapSet.new())}
  end

  @spec visible_entities(t(), id()) :: [id()]
  def visible_entities(%__MODULE__{} = graph, observer_id) do
    graph |> subscription_set(observer_id) |> sorted()
  end

  @spec recipients(t(), id()) :: [id()]
  def recipients(%__MODULE__{} = graph, entity_id) do
    graph |> recipient_set(entity_id) |> sorted()
  end

  @spec route_aabb(t(), AABB.t(), Keyword.t()) :: [id()]
  def route_aabb(%__MODULE__{} = graph, %AABB{} = bounds, opts \\ []) do
    layers = opts |> Keyword.get(:layers, []) |> normalize_layers()
    graph |> matching_observers(bounds, layers) |> sorted()
  end

  @spec route_swept_circle(
          t(),
          {number(), number()},
          {number(), number()},
          non_neg_integer() | float(),
          Keyword.t()
        ) :: [id()]
  def route_swept_circle(%__MODULE__{} = graph, origin, destination, radius, opts \\ []) do
    route_aabb(graph, AABB.swept_circle(origin, destination, radius), opts)
  end

  @spec entity_count(t()) :: non_neg_integer()
  def entity_count(%__MODULE__{} = graph), do: Grid2D.size(graph.entity_grid)

  @spec observer_count(t()) :: non_neg_integer()
  def observer_count(%__MODULE__{} = graph), do: Grid2D.size(graph.observer_grid)

  @spec observer_ids(t()) :: [id()]
  def observer_ids(%__MODULE__{} = graph) do
    graph.observer_layers |> Map.keys() |> Enum.sort()
  end

  ## Private functions

  defp put_entity_state(graph, id, bounds, layers) do
    previous = recipient_set(graph, id)

    graph = %{
      graph
      | entity_grid: Grid2D.put(graph.entity_grid, id, bounds, layers: MapSet.to_list(layers)),
        entity_layers: Map.put(graph.entity_layers, id, layers)
    }

    current = matching_observers(graph, bounds, layers)
    {replace_entity_edges(graph, id, previous, current), previous, current}
  end

  defp delete_entity_state(graph, id) do
    previous = recipient_set(graph, id)

    subscriptions =
      Enum.reduce(previous, graph.subscriptions, fn observer_id, subscriptions ->
        delete_edge(subscriptions, observer_id, id)
      end)

    graph = %{
      graph
      | entity_grid: Grid2D.delete(graph.entity_grid, id),
        entity_layers: Map.delete(graph.entity_layers, id),
        subscriptions: subscriptions,
        recipients: Map.delete(graph.recipients, id)
    }

    {graph, previous}
  end

  defp put_observer_state(graph, id, bounds, layers) do
    previous = subscription_set(graph, id)

    case {Grid2D.fetch(graph.observer_grid, id), Map.get(graph.observer_layers, id)} do
      {{:ok, ^bounds}, ^layers} ->
        {graph, previous, previous}

      {_bounds, _layers} ->
        graph = %{
          graph
          | observer_grid: Grid2D.put(graph.observer_grid, id, bounds),
            observer_layers: Map.put(graph.observer_layers, id, layers)
        }

        current = matching_entities(graph, bounds, layers)
        {replace_observer_edges(graph, id, previous, current), previous, current}
    end
  end

  defp delete_observer_state(graph, id) do
    previous = subscription_set(graph, id)

    recipients =
      Enum.reduce(previous, graph.recipients, fn entity_id, recipients ->
        delete_edge(recipients, entity_id, id)
      end)

    graph = %{
      graph
      | observer_grid: Grid2D.delete(graph.observer_grid, id),
        observer_layers: Map.delete(graph.observer_layers, id),
        subscriptions: Map.delete(graph.subscriptions, id),
        recipients: recipients
    }

    {graph, previous}
  end

  defp matching_observers(graph, bounds, entity_layers) do
    graph.observer_grid
    |> Grid2D.query_aabb(bounds)
    |> Enum.filter(fn observer_id ->
      filters = Map.fetch!(graph.observer_layers, observer_id)
      matches_layers?(entity_layers, filters)
    end)
    |> MapSet.new()
  end

  defp matching_entities(graph, bounds, filters) do
    graph.entity_grid
    |> Grid2D.query_aabb(bounds)
    |> Enum.filter(fn entity_id ->
      entity_layers = Map.fetch!(graph.entity_layers, entity_id)
      matches_layers?(entity_layers, filters)
    end)
    |> MapSet.new()
  end

  defp replace_entity_edges(graph, entity_id, previous, current) do
    subscriptions =
      update_inverse_edges(graph.subscriptions, entity_id, previous, current)

    %{
      graph
      | subscriptions: subscriptions,
        recipients: put_edge_set(graph.recipients, entity_id, current)
    }
  end

  defp replace_observer_edges(graph, observer_id, previous, current) do
    recipients = update_inverse_edges(graph.recipients, observer_id, previous, current)

    %{
      graph
      | recipients: recipients,
        subscriptions: put_edge_set(graph.subscriptions, observer_id, current)
    }
  end

  defp update_inverse_edges(edges, source_id, previous, current) do
    edges =
      previous
      |> MapSet.difference(current)
      |> Enum.reduce(edges, fn target_id, edges -> delete_edge(edges, target_id, source_id) end)

    current
    |> MapSet.difference(previous)
    |> Enum.reduce(edges, fn target_id, edges ->
      Map.update(edges, target_id, MapSet.new([source_id]), &MapSet.put(&1, source_id))
    end)
  end

  defp put_edge_set(edges, id, ids) do
    case MapSet.size(ids) do
      0 -> Map.delete(edges, id)
      _size -> Map.put(edges, id, ids)
    end
  end

  defp delete_edge(edges, id, removed_id) do
    case Map.get(edges, id) do
      nil ->
        edges

      ids ->
        ids
        |> MapSet.delete(removed_id)
        |> then(&put_edge_set(edges, id, &1))
    end
  end

  defp subscription_set(graph, observer_id) do
    Map.get(graph.subscriptions, observer_id, MapSet.new())
  end

  defp recipient_set(graph, entity_id) do
    Map.get(graph.recipients, entity_id, MapSet.new())
  end

  defp normalize_layers(layer) when is_atom(layer), do: MapSet.new([layer])
  defp normalize_layers(layers) when is_list(layers), do: MapSet.new(layers)

  defp matches_layers?(entity_layers, filters) do
    MapSet.size(filters) == 0 or not MapSet.disjoint?(entity_layers, filters)
  end

  defp sorted(ids), do: ids |> MapSet.to_list() |> Enum.sort()
end
