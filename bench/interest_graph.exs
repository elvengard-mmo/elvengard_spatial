# Run with `mix run bench/interest_graph.exs`.

alias ElvenGard.Spatial.{AABB, Grid2D, InterestGraph}

entity_count = String.to_integer(System.get_env("SPATIAL_BENCH_ENTITIES", "1_000"))
observer_count = String.to_integer(System.get_env("SPATIAL_BENCH_OBSERVERS", "100"))
moved_count = String.to_integer(System.get_env("SPATIAL_BENCH_MOVED", "20"))
iteration_count = String.to_integer(System.get_env("SPATIAL_BENCH_ITERATIONS", "500"))
cell_size = 128

entity_entries =
  Enum.map(1..entity_count, fn id ->
    x = rem(id, 50) * 80
    y = div(id, 50) * 80
    layer = if rem(id, 4) == 0, do: :projectiles, else: :players
    {id, AABB.from_circle(x, y, 8), layer}
  end)

observer_entries =
  Enum.map(1..observer_count, fn id ->
    x = rem(id, 20) * 200
    y = div(id, 20) * 240
    {{:observer, id}, AABB.from_circle(x, y, 320), [:players, :projectiles]}
  end)

baseline_grid = Grid2D.put_many(Grid2D.new(cell_size: cell_size), entity_entries)

{graph, _entity_deltas} =
  InterestGraph.put_entities(InterestGraph.new(cell_size: cell_size), entity_entries)

{graph, _observer_deltas} = InterestGraph.put_observers(graph, observer_entries)

observer_views = Map.new(observer_entries, fn {id, bounds, layers} -> {id, {bounds, layers}} end)

verify = fn grid, interest_graph ->
  Enum.each(observer_entries, fn {observer_id, bounds, layers} ->
    expected = Grid2D.query_aabb(grid, bounds, layers: layers)
    ^expected = InterestGraph.visible_entities(interest_graph, observer_id)
  end)
end

verify.(baseline_grid, graph)

updates = fn iteration ->
  offset = if rem(iteration, 2) == 0, do: 120, else: -120

  entity_entries
  |> Enum.take(moved_count)
  |> Enum.map(fn {id, bounds, layer} ->
    moved = AABB.new(bounds.min_x + offset, bounds.min_y, bounds.max_x + offset, bounds.max_y)
    {id, moved, layer}
  end)
end

{baseline_microseconds, baseline_grid} =
  :timer.tc(fn ->
    Enum.reduce(1..iteration_count, baseline_grid, fn iteration, grid ->
      grid = Grid2D.put_many(grid, updates.(iteration))

      Enum.each(observer_views, fn {_observer_id, {bounds, layers}} ->
        _visible = Grid2D.query_aabb(grid, bounds, layers: layers)
      end)

      grid
    end)
  end)

{incremental_microseconds, graph} =
  :timer.tc(fn ->
    Enum.reduce(1..iteration_count, graph, fn iteration, graph ->
      {graph, _deltas} = InterestGraph.apply_entity_changes(graph, updates.(iteration), [])
      graph
    end)
  end)

verify.(baseline_grid, graph)

baseline_average = baseline_microseconds / iteration_count
incremental_average = incremental_microseconds / iteration_count
word_size = :erlang.system_info(:wordsize)

baseline_views =
  Map.new(observer_views, fn {observer_id, {bounds, layers}} ->
    {observer_id, baseline_grid |> Grid2D.query_aabb(bounds, layers: layers) |> MapSet.new()}
  end)

baseline_memory = :erts_debug.size({baseline_grid, baseline_views}) * word_size
graph_memory = :erts_debug.size(graph) * word_size

IO.puts("""
Incremental interest graph benchmark
  entities: #{entity_count}
  observers: #{observer_count}
  moved entities per iteration: #{moved_count}
  iterations: #{iteration_count}
  rebuild observer views average: #{Float.round(baseline_average, 2)} µs
  incremental graph average: #{Float.round(incremental_average, 2)} µs
  reduction: #{Float.round((1 - incremental_average / baseline_average) * 100, 1)}%
  baseline grid + observer views memory: #{baseline_memory} bytes
  interest graph memory: #{graph_memory} bytes
""")
