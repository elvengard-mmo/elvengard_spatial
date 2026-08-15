defmodule ElvenGard.Spatial.InterestGraph.ServerTest do
  use ExUnit.Case, async: true

  alias ElvenGard.Spatial.Grid2D
  alias ElvenGard.Spatial.InterestGraph.Delta
  alias ElvenGard.Spatial.InterestGraph.Server, as: InterestServer
  alias ElvenGard.Spatial.AABB

  test "serves incremental transitions and remains Grid2D.Server compatible" do
    server =
      start_supervised!(
        {InterestServer,
         cell_size: 64, initial_entries: [{:player, AABB.from_circle(0, 0, 5), :players}]}
      )

    assert %Delta{entered: [:player]} =
             InterestServer.put_observer(server, :viewer, AABB.from_circle(0, 0, 50),
               layers: :players
             )

    assert Grid2D.Server.size(server) == 1
    assert Grid2D.Server.ids(server, layers: :players) == [:player]
    assert Grid2D.Server.query_circle(server, {0, 0}, 10) == [:player]

    deltas =
      InterestServer.apply_entity_changes(
        server,
        [{:projectile, AABB.from_circle(10, 0, 2), :projectiles}],
        [:player]
      )

    assert deltas.player == %Delta{entered: [], left: [:viewer], current: []}
    assert deltas.projectile.current == []
    assert InterestServer.visible_entities(server, :viewer) == []

    assert :ok =
             Grid2D.Server.apply_changes(
               server,
               [{:player, AABB.from_circle(500, 0, 5), :players}],
               [:projectile]
             )

    assert Grid2D.Server.query_circle(server, {500, 0}, 10, layers: :players) == [:player]
  end

  test "preserves observers and recomputes their edges across an entity rebuild" do
    server = start_supervised!({InterestServer, cell_size: 100})

    _delta = InterestServer.put_observer(server, :viewer, AABB.from_circle(0, 0, 50))
    assert :ok = Grid2D.Server.replace_all(server, [{:first, AABB.from_circle(0, 0, 5), []}])
    assert InterestServer.visible_entities(server, :viewer) == [:first]

    assert :ok =
             Grid2D.Server.replace_all(server, [{:second, AABB.from_circle(500, 0, 5), []}])

    assert InterestServer.visible_entities(server, :viewer) == []
    assert InterestServer.recipients(server, :first) == []
  end

  test "routes transient effects through the serialized graph" do
    server = start_supervised!({InterestServer, cell_size: 50})

    _delta =
      InterestServer.put_observer(server, :viewer, AABB.from_circle(150, 0, 20),
        layers: :projectiles
      )

    assert InterestServer.route_aabb(server, AABB.from_circle(150, 0, 1), layers: :projectiles) ==
             [:viewer]

    assert InterestServer.route_swept_circle(server, {0, 0}, {300, 0}, 1, layers: :projectiles) ==
             [:viewer]

    assert %Delta{left: []} = InterestServer.delete_observer(server, :viewer)
  end

  test "supports the complete Grid2D server entity API" do
    server = start_supervised!({InterestServer, cell_size: 50})
    first_bounds = AABB.from_circle(0, 0, 5)
    second_bounds = AABB.from_circle(100, 0, 5)

    assert :ok = Grid2D.Server.put(server, :first, first_bounds, layers: :players)
    assert :ok = Grid2D.Server.put_many(server, [{:second, second_bounds, :projectiles}])

    assert Grid2D.Server.query_aabb(server, AABB.from_circle(0, 0, 10)) == [:first]

    assert Grid2D.Server.query_aabbs(server, near: AABB.from_circle(0, 0, 10)) == [
             near: [:first]
           ]

    assert Grid2D.Server.query_swept_circle(server, {-10, 0}, {110, 0}, 1) == [
             :first,
             :second
           ]

    assert :ok = Grid2D.Server.delete(server, :first)
    assert Grid2D.Server.ids(server) == [:second]
  end
end
