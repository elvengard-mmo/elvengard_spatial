defmodule ElvenGard.Spatial.InterestGraph.Server do
  @moduledoc """
  Serializes one mutable `ElvenGard.Spatial.InterestGraph` per game partition.

  Entity messages are compatible with `ElvenGard.Spatial.Grid2D.Server`, so an
  existing ECS indexer or query source can use this server while replication
  consumes incremental observer/entity edge transitions.
  """

  use GenServer

  alias ElvenGard.Spatial.InterestGraph.Delta
  alias ElvenGard.Spatial.{AABB, Grid2D, InterestGraph}

  @type query_key :: any()

  ## Public API

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    case name do
      nil -> GenServer.start_link(__MODULE__, opts)
      server_name -> GenServer.start_link(__MODULE__, opts, name: server_name)
    end
  end

  @spec put_observer(GenServer.server(), InterestGraph.id(), AABB.t(), Keyword.t()) :: Delta.t()
  def put_observer(server, observer_id, %AABB{} = bounds, opts \\ []) do
    GenServer.call(server, {:put_observer, observer_id, bounds, opts})
  end

  @spec delete_observer(GenServer.server(), InterestGraph.id()) :: Delta.t()
  def delete_observer(server, observer_id) do
    GenServer.call(server, {:delete_observer, observer_id})
  end

  @spec sync_observers(GenServer.server(), [InterestGraph.entry()]) ::
          %{optional(InterestGraph.id()) => Delta.t()}
  def sync_observers(server, entries) when is_list(entries) do
    GenServer.call(server, {:sync_observers, entries})
  end

  @spec sync_observer_views(GenServer.server(), [InterestGraph.entry()]) ::
          %{optional(InterestGraph.id()) => MapSet.t(InterestGraph.id())}
  def sync_observer_views(server, entries) when is_list(entries) do
    GenServer.call(server, {:sync_observer_views, entries})
  end

  @spec observer_ids(GenServer.server()) :: [InterestGraph.id()]
  def observer_ids(server) do
    GenServer.call(server, :observer_ids)
  end

  @spec visible_entities(GenServer.server(), InterestGraph.id()) :: [InterestGraph.id()]
  def visible_entities(server, observer_id) do
    GenServer.call(server, {:visible_entities, observer_id})
  end

  @spec recipients(GenServer.server(), InterestGraph.id()) :: [InterestGraph.id()]
  def recipients(server, entity_id) do
    GenServer.call(server, {:recipients, entity_id})
  end

  @spec apply_entity_changes(
          GenServer.server(),
          [InterestGraph.entry()],
          [InterestGraph.id()]
        ) :: %{optional(InterestGraph.id()) => Delta.t()}
  def apply_entity_changes(server, put_entries, deleted_ids) do
    GenServer.call(server, {:apply_entity_changes, put_entries, deleted_ids})
  end

  @spec route_aabb(GenServer.server(), AABB.t(), Keyword.t()) :: [InterestGraph.id()]
  def route_aabb(server, %AABB{} = bounds, opts \\ []) do
    GenServer.call(server, {:route_aabb, bounds, opts})
  end

  @spec route_swept_circle(
          GenServer.server(),
          {number(), number()},
          {number(), number()},
          non_neg_integer() | float(),
          Keyword.t()
        ) :: [InterestGraph.id()]
  def route_swept_circle(server, origin, destination, radius, opts \\ []) do
    GenServer.call(server, {:route_swept_circle, origin, destination, radius, opts})
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    {initial_entries, graph_opts} = Keyword.pop(opts, :initial_entries, [])

    {graph, _deltas} =
      graph_opts |> InterestGraph.new() |> InterestGraph.put_entities(initial_entries)

    {:ok, graph}
  end

  @impl true
  def handle_call(:size, _from, graph) do
    {:reply, InterestGraph.entity_count(graph), graph}
  end

  def handle_call({:ids, opts}, _from, graph) do
    {:reply, Grid2D.ids(graph.entity_grid, opts), graph}
  end

  def handle_call({:put, id, bounds, opts}, _from, graph) do
    layers = Keyword.get(opts, :layers, [])
    graph = InterestGraph.update_entities(graph, [{id, bounds, layers}], [])
    {:reply, :ok, graph}
  end

  def handle_call({:put_many, entries}, _from, graph) do
    graph = InterestGraph.update_entities(graph, entries, [])
    {:reply, :ok, graph}
  end

  def handle_call({:replace_all, entries}, _from, graph) do
    {:reply, :ok, InterestGraph.replace_entities(graph, entries)}
  end

  def handle_call({:apply_changes, put_entries, deleted_ids}, _from, graph) do
    graph = InterestGraph.update_entities(graph, put_entries, deleted_ids)
    {:reply, :ok, graph}
  end

  def handle_call({:delete, id}, _from, graph) do
    graph = InterestGraph.update_entities(graph, [], [id])
    {:reply, :ok, graph}
  end

  def handle_call({:query_aabb, bounds, opts}, _from, graph) do
    {:reply, Grid2D.query_aabb(graph.entity_grid, bounds, opts), graph}
  end

  def handle_call({:query_aabbs, queries, opts}, _from, graph) do
    results =
      Enum.map(queries, fn {key, bounds} ->
        {key, Grid2D.query_aabb(graph.entity_grid, bounds, opts)}
      end)

    {:reply, results, graph}
  end

  def handle_call({:query_circle, center, radius, opts}, _from, graph) do
    {:reply, Grid2D.query_circle(graph.entity_grid, center, radius, opts), graph}
  end

  def handle_call({:query_swept_circle, origin, destination, radius, opts}, _from, graph) do
    result = Grid2D.query_swept_circle(graph.entity_grid, origin, destination, radius, opts)
    {:reply, result, graph}
  end

  def handle_call({:put_observer, observer_id, bounds, opts}, _from, graph) do
    {graph, delta} = InterestGraph.put_observer(graph, observer_id, bounds, opts)
    {:reply, delta, graph}
  end

  def handle_call({:delete_observer, observer_id}, _from, graph) do
    {graph, delta} = InterestGraph.delete_observer(graph, observer_id)
    {:reply, delta, graph}
  end

  def handle_call({:sync_observers, entries}, _from, graph) do
    {graph, deltas} = InterestGraph.sync_observers(graph, entries)
    {:reply, deltas, graph}
  end

  def handle_call({:sync_observer_views, entries}, _from, graph) do
    {graph, views} = InterestGraph.sync_observer_views(graph, entries)
    {:reply, views, graph}
  end

  def handle_call(:observer_ids, _from, graph) do
    {:reply, InterestGraph.observer_ids(graph), graph}
  end

  def handle_call({:visible_entities, observer_id}, _from, graph) do
    {:reply, InterestGraph.visible_entities(graph, observer_id), graph}
  end

  def handle_call({:recipients, entity_id}, _from, graph) do
    {:reply, InterestGraph.recipients(graph, entity_id), graph}
  end

  def handle_call({:apply_entity_changes, put_entries, deleted_ids}, _from, graph) do
    {graph, deltas} = InterestGraph.apply_entity_changes(graph, put_entries, deleted_ids)
    {:reply, deltas, graph}
  end

  def handle_call({:route_aabb, bounds, opts}, _from, graph) do
    {:reply, InterestGraph.route_aabb(graph, bounds, opts), graph}
  end

  def handle_call({:route_swept_circle, origin, destination, radius, opts}, _from, graph) do
    recipients = InterestGraph.route_swept_circle(graph, origin, destination, radius, opts)
    {:reply, recipients, graph}
  end
end
