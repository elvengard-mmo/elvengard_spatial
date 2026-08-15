defmodule ElvenGard.Spatial.InterestGraphTest do
  use ExUnit.Case, async: true

  alias ElvenGard.Spatial.InterestGraph.Delta
  alias ElvenGard.Spatial.{AABB, InterestGraph}

  test "maintains reciprocal edges as an entity enters and leaves an observer" do
    graph = InterestGraph.new(cell_size: 100)
    {graph, _delta} = InterestGraph.put_observer(graph, :viewer, AABB.from_circle(0, 0, 100))

    {graph, entered} =
      InterestGraph.put_entity(graph, :player, AABB.from_circle(50, 0, 10), layers: :players)

    assert entered == %Delta{entered: [:viewer], left: [], current: [:viewer]}
    assert InterestGraph.visible_entities(graph, :viewer) == [:player]
    assert InterestGraph.recipients(graph, :player) == [:viewer]

    {graph, left} =
      InterestGraph.put_entity(graph, :player, AABB.from_circle(500, 0, 10), layers: :players)

    assert left == %Delta{entered: [], left: [:viewer], current: []}
    assert InterestGraph.visible_entities(graph, :viewer) == []
    assert InterestGraph.recipients(graph, :player) == []
  end

  test "recomputes only one observer's edges when its viewport moves" do
    {graph, _deltas} =
      InterestGraph.new(cell_size: 64)
      |> InterestGraph.put_entities([
        {:left, AABB.from_circle(0, 0, 5), :players},
        {:right, AABB.from_circle(500, 0, 5), :players}
      ])

    {graph, first} =
      InterestGraph.put_observer(graph, :viewer, AABB.from_circle(0, 0, 50), layers: :players)

    assert first == %Delta{entered: [:left], left: [], current: [:left]}

    {graph, moved} =
      InterestGraph.put_observer(graph, :viewer, AABB.from_circle(500, 0, 50), layers: :players)

    assert moved == %Delta{entered: [:right], left: [:left], current: [:right]}
    assert InterestGraph.recipients(graph, :left) == []
    assert InterestGraph.recipients(graph, :right) == [:viewer]
  end

  test "filters entity layers independently for each observer" do
    {graph, _deltas} =
      InterestGraph.new()
      |> InterestGraph.put_entities([
        {:player, AABB.from_circle(0, 0, 5), [:actors, :players]},
        {:projectile, AABB.from_circle(10, 0, 2), :projectiles}
      ])

    {graph, _delta} =
      InterestGraph.put_observer(graph, :player_view, AABB.from_circle(0, 0, 100),
        layers: :players
      )

    {graph, _delta} =
      InterestGraph.put_observer(graph, :all_view, AABB.from_circle(0, 0, 100))

    assert InterestGraph.visible_entities(graph, :player_view) == [:player]
    assert InterestGraph.visible_entities(graph, :all_view) == [:player, :projectile]
    assert InterestGraph.recipients(graph, :projectile) == [:all_view]
  end

  test "keeps adjacent-cell visibility exact at a viewport border" do
    graph = InterestGraph.new(cell_size: 100)

    {graph, _delta} =
      InterestGraph.put_observer(graph, :viewer, AABB.new(90, -20, 110, 20))

    {graph, touching} =
      InterestGraph.put_entity(graph, :touching, AABB.new(110, 0, 120, 10))

    {graph, outside} =
      InterestGraph.put_entity(graph, :outside, AABB.new(111, 0, 120, 10))

    assert touching.current == [:viewer]
    assert outside.current == []
    assert InterestGraph.visible_entities(graph, :viewer) == [:touching]
  end

  test "routes a swept projectile through every crossed cell without changing subscriptions" do
    graph = InterestGraph.new(cell_size: 50)

    {graph, _deltas} =
      InterestGraph.put_observers(graph, [
        {:start, AABB.from_circle(0, 0, 20), :projectiles},
        {:middle, AABB.from_circle(250, 0, 20), :projectiles},
        {:end, AABB.from_circle(500, 0, 20), :projectiles},
        {:players_only, AABB.from_circle(250, 0, 20), :players},
        {:outside, AABB.from_circle(250, 100, 20), :projectiles}
      ])

    assert InterestGraph.route_swept_circle(graph, {-10, 0}, {510, 0}, 2, layers: :projectiles) ==
             [:end, :middle, :start]

    assert InterestGraph.visible_entities(graph, :middle) == []
  end

  test "deleting entities and observers removes both sides of every edge" do
    graph = InterestGraph.new()
    {graph, _delta} = InterestGraph.put_entity(graph, :entity, AABB.from_circle(0, 0, 5))
    {graph, _delta} = InterestGraph.put_observer(graph, :first, AABB.from_circle(0, 0, 10))
    {graph, _delta} = InterestGraph.put_observer(graph, :second, AABB.from_circle(0, 0, 10))

    {graph, observer_delta} = InterestGraph.delete_observer(graph, :first)
    assert observer_delta.left == [:entity]
    assert InterestGraph.recipients(graph, :entity) == [:second]

    {graph, entity_delta} = InterestGraph.delete_entity(graph, :entity)
    assert entity_delta.left == [:second]
    assert InterestGraph.visible_entities(graph, :second) == []
    assert InterestGraph.entity_count(graph) == 0
    assert InterestGraph.observer_count(graph) == 1
  end

  test "synchronizes the complete observer set and skips unchanged viewports" do
    {graph, _deltas} =
      InterestGraph.new()
      |> InterestGraph.put_entities([
        {:left, AABB.from_circle(0, 0, 5), :players},
        {:right, AABB.from_circle(500, 0, 5), :players}
      ])

    {graph, deltas} =
      InterestGraph.sync_observers(graph, [
        {:first, AABB.from_circle(0, 0, 50), :players},
        {:stale, AABB.from_circle(500, 0, 50), :players}
      ])

    assert deltas.first.current == [:left]
    assert deltas.stale.current == [:right]

    {same_graph, deltas} =
      InterestGraph.sync_observers(graph, [
        {:first, AABB.from_circle(0, 0, 50), :players}
      ])

    assert deltas.first == %Delta{entered: [], left: [], current: [:left]}
    assert deltas.stale == %Delta{entered: [], left: [:right], current: []}
    assert InterestGraph.observer_ids(same_graph) == [:first]
    assert InterestGraph.recipients(same_graph, :right) == []
  end

  test "updates entity edges without materializing transition deltas" do
    {graph, _delta} =
      InterestGraph.new()
      |> InterestGraph.put_observer(:viewer, AABB.from_circle(0, 0, 50), layers: :players)

    graph =
      InterestGraph.update_entities(
        graph,
        [{:player, AABB.from_circle(0, 0, 5), :players}],
        []
      )

    assert InterestGraph.visible_entities(graph, :viewer) == [:player]
    assert InterestGraph.recipients(graph, :player) == [:viewer]

    graph = InterestGraph.update_entities(graph, [], [:player])

    assert InterestGraph.visible_entities(graph, :viewer) == []
    assert InterestGraph.recipients(graph, :player) == []
  end

  test "synchronizes observer views without sorting transition lists" do
    {graph, _deltas} =
      InterestGraph.new()
      |> InterestGraph.put_entities([
        {:left, AABB.from_circle(0, 0, 5), :players},
        {:right, AABB.from_circle(500, 0, 5), :players}
      ])

    {graph, views} =
      InterestGraph.sync_observer_views(graph, [
        {:first, AABB.from_circle(0, 0, 50), :players},
        {:stale, AABB.from_circle(500, 0, 50), :players}
      ])

    assert views == %{first: MapSet.new([:left]), stale: MapSet.new([:right])}

    {graph, views} =
      InterestGraph.sync_observer_views(graph, [
        {:first, AABB.from_circle(0, 0, 50), :players}
      ])

    assert views == %{first: MapSet.new([:left])}
    assert InterestGraph.observer_ids(graph) == [:first]
    assert InterestGraph.recipients(graph, :right) == []
  end
end
