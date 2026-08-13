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
