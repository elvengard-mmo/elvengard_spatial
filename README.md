# ElvenGard Spatial

Deterministic spatial broad-phase primitives for real-time Elixir games.

The library indexes opaque entity identifiers in a configurable 2D uniform
grid. It selects nearby candidates for collision detection, area of interest,
targeting, auras, AI perception, and replication while leaving exact geometry
and gameplay rules to the consuming game.

```elixir
alias ElvenGard.Spatial.{AABB, Grid2D}

grid =
  Grid2D.new(cell_size: 128)
  |> Grid2D.put(:player_1, AABB.from_circle(100, 200, 24), layers: :players)

candidates =
  Grid2D.query_swept_circle(
    grid,
    {0, 200},
    {300, 200},
    8,
    layers: :players
  )
```

`candidates` contains broad-phase candidates only. The caller must still run
its exact collision test before applying game rules.

## Partition-owned indexes

`ElvenGard.Spatial.Grid2D.Server` serializes incremental updates and queries
against one grid. A game room can supervise one server and share its name or
PID with systems that require spatial candidates:

```elixir
{:ok, index} = ElvenGard.Spatial.Grid2D.Server.start_link(cell_size: 128)

:ok =
  ElvenGard.Spatial.Grid2D.Server.put(
    index,
    :player_1,
    AABB.from_circle(100, 200, 24),
    layers: :players
  )
```

Queries are synchronous and observe a complete grid before or after each
update. Pass `initial_entries: entries` to publish a rebuilt index atomically
when its server starts. Use `replace_all/2` for later full rebuilds, then
maintain the index with `put/4`, `put_many/2`, and `delete/2`.
`Grid2D.ids/2` and `Grid2D.Server.ids/2` return every indexed identifier,
optionally restricted with `layers:`, without walking a synthetic world area.

## Incremental area of interest

`ElvenGard.Spatial.InterestGraph` maintains both sides of visibility edges:
the entities visible to each observer and the observers receiving one entity.
Moving an item updates only its own candidate edges instead of rebuilding every
player view:

```elixir
alias ElvenGard.Spatial.{AABB, InterestGraph}

graph = InterestGraph.new(cell_size: 128)
{graph, _delta} = InterestGraph.put_observer(graph, :client, AABB.from_circle(0, 0, 500))
{graph, delta} = InterestGraph.put_entity(graph, :player, AABB.from_circle(100, 0, 24))

delta.entered
#=> [:client]
```

Observer filters select entity layers such as `:players` or `:projectiles`.
`route_swept_circle/5` finds observers intersecting a complete trajectory, so a
fast projectile cannot disappear between static cells. `InterestGraph.Server`
serializes a graph per room and accepts the existing `Grid2D.Server` entity
query/update messages, allowing ECS query sources and indexers to keep using
the same process without a duplicate entity grid.

Use `InterestGraph.Server.sync_observers/2` to replace the current room
observer set in one serialized call. Unchanged viewports reuse their existing
edges, and observers absent from the new set are removed immediately.

## ECS queries

The optional `elvengard_ecs` integration exposes spatial candidate sources:

```elixir
source =
  ElvenGard.Spatial.ECS.QuerySource.circle(
    index,
    room_partition,
    {100, 200},
    500,
    layers: :players
  )

nearby =
  {ElvenGard.ECS.Entity, Position, Combat}
  |> ElvenGard.ECS.Query.select(
    with: :selected,
    partition: room_partition,
    source: source
  )
  |> ElvenGard.ECS.Query.all()
```

Use `ElvenGard.Spatial.ECS.QuerySource.all/3` with `layers:` when a system
needs one complete indexed category, such as every player or projectile in a
room, but must avoid loading unrelated ECS entities.

The grid supplies candidate IDs before Mnesia loads the selected components.
`ElvenGard.Spatial.ECS.Indexer.sync/5` applies a committed ECS change set to
the grid in one incremental batch. The application supplies the indexed
component and a projector that returns `{bounds, layers}`.

## Installation

Until the package is published to Hex, point the dependency at `main`:

```elixir
def deps() do
  [
    {:elvengard_spatial,
     github: "elvengard-mmo/elvengard_spatial", branch: "main"}
  ]
end
```

The spatial core has no runtime dependencies and supports Elixir 1.15 or
newer. The optional ECS integration is available when the consuming project
also depends on `elvengard_ecs`.

## Benchmarks

Run the deterministic exhaustive-scan comparison with:

```shell
mix run bench/grid_2d.exs
mix run bench/interest_graph.exs
```

The benchmark verifies that every indexed query returns exactly the same AABB
candidates as a full scan before reporting timings.

## Design contract

- Entity identifiers are opaque Erlang terms.
- `Grid2D` updates are immutable and unchanged bounds are no-ops.
- `Grid2D.Server` serializes mutations around one immutable grid value.
- `InterestGraph` incrementally maintains reciprocal observer/entity edges.
- `InterestGraph.Server` is a drop-in superset for `Grid2D.Server` entity operations.
- Layers only filter broad-phase candidates.
- Query results use Erlang term ordering for deterministic simulations.
- Circle and swept-circle queries return AABB candidates and may contain false
  positives, but never discard an intersecting AABB.
