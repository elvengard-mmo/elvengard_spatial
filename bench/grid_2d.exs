alias ElvenGard.Spatial.{AABB, Grid2D}

defmodule Grid2DBenchmark do
  @moduledoc false

  ## Public API

  def run() do
    IO.puts("entities sweeps naive avg/p95 spatial avg/p95 speedup candidates")

    Enum.each(
      [
        %{entities: 100, sweeps: 300, iterations: 200},
        %{entities: 1_000, sweeps: 300, iterations: 60},
        %{entities: 10_000, sweeps: 300, iterations: 15}
      ],
      &run_scenario/1
    )
  end

  ## Private functions

  defp run_scenario(scenario) do
    entries = build_entries(scenario.entities)
    sweeps = build_sweeps(entries, scenario.sweeps)
    grid = Grid2D.put_many(Grid2D.new(cell_size: 128), entries)

    expected = query_naively(entries, sweeps)
    actual = query_spatially(grid, sweeps)

    unless actual == expected do
      raise "spatial results differ from the exhaustive reference"
    end

    naive = measure(fn -> query_naively(entries, sweeps) end, scenario.iterations)
    spatial = measure(fn -> query_spatially(grid, sweeps) end, scenario.iterations)
    candidates = expected |> Enum.map(&length/1) |> average()

    IO.puts(
      Enum.join(
        [
          pad(scenario.entities, 8),
          pad(scenario.sweeps, 6),
          pad_timing(naive),
          pad_timing(spatial),
          String.pad_leading(format_float(naive.average_us / spatial.average_us), 7) <> "x",
          String.pad_leading(format_float(candidates), 10)
        ],
        " "
      )
    )
  end

  defp build_entries(count) do
    columns = ceil(:math.sqrt(count))
    rows = ceil(count / columns)

    Enum.map(0..(count - 1), fn index ->
      column = rem(index, columns)
      row = div(index, columns)
      x = (column - (columns - 1) / 2) * 280.0
      y = (row - (rows - 1) / 2) * 190.0
      {index, AABB.from_circle(x, y, 24.0), :players}
    end)
  end

  defp build_sweeps(entries, count) do
    entries
    |> Stream.cycle()
    |> Enum.take(count)
    |> Enum.with_index()
    |> Enum.map(fn {{_id, bounds, _layer}, index} ->
      origin = {bounds.min_x - 16.0, (bounds.min_y + bounds.max_y) / 2}
      distance = 30.0 + rem(index, 5) * 20.0
      destination = {elem(origin, 0) + distance, elem(origin, 1)}
      AABB.swept_circle(origin, destination, 8.0)
    end)
  end

  defp query_naively(entries, sweeps) do
    Enum.map(sweeps, fn sweep ->
      entries
      |> Enum.filter(fn {_id, bounds, _layer} -> AABB.intersects?(bounds, sweep) end)
      |> Enum.map(&elem(&1, 0))
    end)
  end

  defp query_spatially(grid, sweeps) do
    Enum.map(sweeps, &Grid2D.query_aabb(grid, &1, layers: :players))
  end

  defp measure(function, iterations) do
    Enum.each(1..5, fn _iteration -> function.() end)

    samples =
      Enum.map(1..iterations, fn _iteration ->
        started_at = System.monotonic_time(:microsecond)
        function.()
        System.monotonic_time(:microsecond) - started_at
      end)

    sorted = Enum.sort(samples)

    %{
      average_us: average(samples),
      p95_us: Enum.at(sorted, ceil(length(sorted) * 0.95) - 1)
    }
  end

  defp average(values), do: Enum.sum(values) / length(values)

  defp pad_timing(stats) do
    String.pad_leading("#{format_float(stats.average_us)}/#{stats.p95_us}", 15)
  end

  defp pad(value, width), do: value |> Integer.to_string() |> String.pad_leading(width)
  defp format_float(value), do: :erlang.float_to_binary(value * 1.0, decimals: 1)
end

Grid2DBenchmark.run()
