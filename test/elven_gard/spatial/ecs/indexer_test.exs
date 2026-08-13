defmodule ElvenGard.Spatial.ECS.IndexerTest do
  use ExUnit.Case, async: true

  alias ElvenGard.ECS.{Command, Entity, Multi}
  alias ElvenGard.Spatial.AABB
  alias ElvenGard.Spatial.ECS.{Indexer, QuerySource}
  alias ElvenGard.Spatial.Grid2D.Server
  alias ElvenGard.Spatial.TestPosition

  test "applies committed component changes incrementally" do
    partition = make_ref()
    server = start_supervised!({Server, cell_size: 100})

    spawn =
      Multi.new()
      |> Multi.spawn_entity(
        :spawn,
        Entity.entity_spec(
          partition: partition,
          components: [%TestPosition{x: 0.0, y: 0.0}]
        )
      )

    {:ok, %{spawn: {entity, _components}}, spawn_changes} =
      Command.transact_with_changes(spawn)

    :ok = Indexer.sync(server, spawn_changes, TestPosition, &project/2)
    assert candidates(server, partition, {0, 0}) == [entity.id]

    move =
      Multi.new()
      |> Multi.replace_component(
        :move,
        entity,
        %TestPosition{x: 1_000.0, y: 1_000.0}
      )

    {:ok, _results, move_changes} = Command.transact_with_changes(move)
    :ok = Indexer.sync(server, move_changes, TestPosition, &project/2)

    assert candidates(server, partition, {0, 0}) == []
    assert candidates(server, partition, {1_000, 1_000}) == [entity.id]

    despawn = Multi.despawn_entity(Multi.new(), :despawn, entity)
    {:ok, _results, despawn_changes} = Command.transact_with_changes(despawn)
    :ok = Indexer.sync(server, despawn_changes, TestPosition, &project/2)

    assert candidates(server, partition, {1_000, 1_000}) == []
  end

  test "indexes entities entering a partition and removes entities leaving it" do
    first_partition = make_ref()
    second_partition = make_ref()
    first_server = start_supervised!({Server, [cell_size: 100]}, id: make_ref())
    second_server = start_supervised!({Server, [cell_size: 100]}, id: make_ref())

    spec =
      Entity.entity_spec(
        partition: first_partition,
        components: [%TestPosition{x: 100.0, y: 100.0}]
      )

    {:ok, {entity, _components}} = Command.spawn_entity(spec)
    on_exit(fn -> Command.despawn_entity(entity) end)

    :ok = Server.put(first_server, entity.id, AABB.from_circle(100, 100, 10), layers: :actors)

    move = Multi.set_partition(Multi.new(), :move, entity, second_partition)
    {:ok, _results, changes} = Command.transact_with_changes(move)

    :ok =
      Indexer.sync(first_server, changes, TestPosition, &project/2, partition: first_partition)

    :ok =
      Indexer.sync(second_server, changes, TestPosition, &project/2, partition: second_partition)

    assert candidates(first_server, first_partition, {100, 100}) == []
    assert candidates(second_server, second_partition, {100, 100}) == [entity.id]
  end

  test "removes deleted or ignored indexed components" do
    partition = make_ref()
    server = start_supervised!({Server, cell_size: 100})

    spec =
      Entity.entity_spec(
        partition: partition,
        components: [%TestPosition{x: 100.0, y: 100.0}]
      )

    {:ok, {entity, _components}} = Command.spawn_entity(spec)
    on_exit(fn -> Command.despawn_entity(entity) end)
    :ok = Server.put(server, entity.id, AABB.from_circle(100, 100, 10), layers: :actors)

    ignore =
      Multi.replace_component(
        Multi.new(),
        :ignore,
        entity,
        %TestPosition{x: -1.0, y: 100.0}
      )

    {:ok, _results, ignore_changes} = Command.transact_with_changes(ignore)
    :ok = Indexer.sync(server, ignore_changes, TestPosition, &project/2)
    assert candidates(server, partition, {100, 100}) == []

    add = Multi.replace_component(Multi.new(), :add, entity, %TestPosition{x: 0.0, y: 0.0})
    {:ok, _results, add_changes} = Command.transact_with_changes(add)
    :ok = Indexer.sync(server, add_changes, TestPosition, &project/2)
    assert candidates(server, partition, {0, 0}) == [entity.id]

    delete = Multi.delete_component(Multi.new(), :delete, entity, TestPosition)
    {:ok, _results, delete_changes} = Command.transact_with_changes(delete)
    :ok = Indexer.sync(server, delete_changes, TestPosition, &project/2)
    assert candidates(server, partition, {0, 0}) == []
  end

  test "ignores unrelated changes and rejects invalid indexed state" do
    partition = make_ref()
    server = start_supervised!({Server, cell_size: 100})

    {:ok, %{spawn: {entity, []}}, no_position_changes} =
      Multi.new()
      |> Multi.spawn_entity(:spawn, Entity.entity_spec(partition: partition))
      |> Command.transact_with_changes()

    on_exit(fn -> Command.despawn_entity(entity) end)

    assert :ok = Indexer.sync(server, no_position_changes, TestPosition, &project/2)
    assert Server.size(server) == 0

    duplicate_positions =
      Entity.entity_spec(
        partition: partition,
        components: [
          %TestPosition{x: 0.0, y: 0.0},
          %TestPosition{x: 10.0, y: 10.0}
        ]
      )

    {:ok, %{spawn: {duplicate, _components}}, duplicate_changes} =
      Multi.new()
      |> Multi.spawn_entity(:spawn, duplicate_positions)
      |> Command.transact_with_changes()

    on_exit(fn -> Command.despawn_entity(duplicate) end)

    assert_raise ArgumentError, ~r/must be single-valued/, fn ->
      Indexer.sync(server, duplicate_changes, TestPosition, &project/2)
    end

    single_position =
      Multi.replace_component(
        Multi.new(),
        :replace,
        duplicate,
        %TestPosition{x: 0.0, y: 0.0}
      )

    {:ok, _results, single_changes} = Command.transact_with_changes(single_position)

    assert_raise ArgumentError, ~r/spatial projector returned invalid projection/, fn ->
      Indexer.sync(server, single_changes, TestPosition, fn _entity, _position -> :invalid end)
    end
  end

  defp candidates(server, partition, center) do
    server
    |> QuerySource.circle(partition, center, 50, layers: :actors)
    |> ElvenGard.ECS.Query.Source.resolve(partition)
  end

  defp project(_entity, position) do
    case position.x < 0 do
      true -> :ignore
      false -> {AABB.from_circle(position.x, position.y, position.radius), :actors}
    end
  end
end
