defmodule ElvenGard.Spatial.Grid2D.ServerTest do
  use ExUnit.Case, async: true

  alias ElvenGard.Spatial.AABB
  alias ElvenGard.Spatial.Grid2D.Server

  test "serializes incremental updates and spatial queries" do
    server = start_supervised!({Server, cell_size: 100})

    :ok = Server.put(server, :player, AABB.from_circle(0, 0, 10), layers: :players)
    :ok = Server.put(server, :wall, AABB.new(90, -20, 110, -10), layers: :obstacles)

    assert Server.size(server) == 2
    assert Server.query_circle(server, {0, 0}, 20, layers: :players) == [:player]

    :ok = Server.put(server, :player, AABB.from_circle(1_000, 1_000, 10), layers: :players)

    assert Server.query_circle(server, {0, 0}, 20, layers: :players) == []
    assert Server.query_circle(server, {1_000, 1_000}, 20, layers: :players) == [:player]

    :ok =
      Server.apply_changes(
        server,
        [{:replacement, AABB.from_circle(1_100, 1_000, 10), :players}],
        [:player]
      )

    assert Server.query_circle(server, {1_000, 1_000}, 20, layers: :players) == []
    assert Server.query_circle(server, {1_100, 1_000}, 20, layers: :players) == [:replacement]

    :ok = Server.delete(server, :replacement)
    assert Server.size(server) == 1
  end

  test "atomically replaces the complete grid" do
    server = start_supervised!({Server, cell_size: 50})

    :ok =
      Server.put_many(server, [
        {:stale, AABB.from_circle(0, 0, 5), []},
        {:also_stale, AABB.from_circle(20, 0, 5), []}
      ])

    assert Server.query_aabb(server, AABB.new(-10, -10, 30, 10)) == [:also_stale, :stale]

    :ok =
      Server.replace_all(server, [
        {:first, AABB.from_circle(100, 0, 5), :actors},
        {:second, AABB.from_circle(200, 0, 5), :actors}
      ])

    assert Server.query_circle(server, {0, 0}, 10) == []
    assert Server.query_circle(server, {20, 0}, 10) == []

    assert Server.query_swept_circle(server, {90, 0}, {210, 0}, 2, layers: :actors) == [
             :first,
             :second
           ]
  end
end
