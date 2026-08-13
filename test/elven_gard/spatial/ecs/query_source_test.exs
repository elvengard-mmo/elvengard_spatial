defmodule ElvenGard.Spatial.ECS.QuerySourceTest do
  use ExUnit.Case, async: true

  alias ElvenGard.ECS.{Command, Entity, Query}
  alias ElvenGard.Spatial.AABB
  alias ElvenGard.Spatial.ECS.QuerySource
  alias ElvenGard.Spatial.Grid2D.Server
  alias ElvenGard.Spatial.TestPosition

  test "loads ECS components only for spatial candidates" do
    partition = make_ref()
    server = start_supervised!({Server, cell_size: 100})

    near = spawn_entity(partition, %TestPosition{x: 10.0, y: 20.0})
    far = spawn_entity(partition, %TestPosition{x: 1_000.0, y: 1_000.0})

    on_exit(fn ->
      Command.despawn_entity(near)
      Command.despawn_entity(far)
    end)

    :ok = Server.put(server, near.id, AABB.from_circle(10, 20, 10))
    :ok = Server.put(server, far.id, AABB.from_circle(1_000, 1_000, 10))

    source = QuerySource.circle(server, partition, {0, 0}, 100)

    results =
      {Entity, TestPosition}
      |> Query.select(with: :selected, partition: partition, source: source)
      |> Query.all()

    assert results == [{near, %TestPosition{x: 10.0, y: 20.0}}]
  end

  test "rejects a query against another partition" do
    server = start_supervised!({Server, cell_size: 100})
    source = QuerySource.aabb(server, :first_partition, AABB.new(0, 0, 100, 100))
    query = Query.select(Entity, partition: :second_partition, source: source)

    assert_raise ArgumentError, ~r/spatial source belongs to/, fn ->
      Query.all(query)
    end
  end

  test "supports AABB and swept-circle candidate sources" do
    partition = make_ref()
    server = start_supervised!({Server, cell_size: 50})

    :ok = Server.put(server, :first, AABB.from_circle(0, 0, 5), layers: :actors)
    :ok = Server.put(server, :second, AABB.from_circle(100, 0, 5), layers: :actors)
    :ok = Server.put(server, :ignored, AABB.from_circle(50, 50, 5), layers: :obstacles)

    aabb = QuerySource.aabb(server, partition, AABB.new(-10, -10, 10, 10), layers: :actors)

    swept = QuerySource.swept_circle(server, partition, {-10, 0}, {110, 0}, 2)

    assert ElvenGard.ECS.Query.Source.resolve(aabb, partition) == [:first]
    assert ElvenGard.ECS.Query.Source.resolve(swept, partition) == [:first, :second]
  end

  defp spawn_entity(partition, position) do
    spec = Entity.entity_spec(partition: partition, components: [position])
    {:ok, {entity, _components}} = Command.spawn_entity(spec)
    entity
  end
end
