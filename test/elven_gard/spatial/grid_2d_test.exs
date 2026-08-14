defmodule ElvenGard.Spatial.Grid2DTest do
  use ExUnit.Case, async: true

  alias ElvenGard.Spatial.{AABB, Grid2D}

  test "indexes and deterministically queries entities across cell boundaries" do
    grid =
      Grid2D.new(cell_size: 100)
      |> Grid2D.put(:right, AABB.from_circle(105, 20, 10), layers: :players)
      |> Grid2D.put(:left, AABB.from_circle(95, 20, 10), layers: :players)
      |> Grid2D.put(:wall, AABB.new(90, -20, 110, -10), layers: :obstacles)

    assert Grid2D.query_aabb(grid, AABB.new(90, 0, 110, 40)) == [:left, :right]

    assert Grid2D.query_aabb(grid, AABB.new(80, -30, 120, 40), layers: :obstacles) == [
             :wall
           ]
  end

  test "updates an existing entity without retaining stale cells" do
    grid =
      Grid2D.new(cell_size: 100)
      |> Grid2D.put(:player, AABB.from_circle(0, 0, 10), layers: :players)
      |> Grid2D.put(:player, AABB.from_circle(1_000, 1_000, 10), layers: :players)

    assert Grid2D.query_circle(grid, {0, 0}, 20) == []
    assert Grid2D.query_circle(grid, {1_000, 1_000}, 20) == [:player]
    assert Grid2D.fetch(grid, :player) == {:ok, AABB.new(990, 990, 1_010, 1_010)}
  end

  test "returns the existing grid when indexed bounds and layers are unchanged" do
    grid =
      Grid2D.new()
      |> Grid2D.put(:player, AABB.from_circle(0, 0, 10), layers: :players)

    assert Grid2D.put(grid, :player, AABB.from_circle(0, 0, 10), layers: :players) === grid
  end

  test "deletes entities and empty cells" do
    grid =
      Grid2D.new()
      |> Grid2D.put(:player, AABB.from_circle(0, 0, 10), layers: :players)
      |> Grid2D.delete(:player)

    assert Grid2D.size(grid) == 0
    assert Grid2D.fetch(grid, :player) == :error
    assert grid.cells == %{}
  end

  test "batch insertion and swept-circle queries cover a complete trajectory" do
    grid =
      Grid2D.new(cell_size: 50)
      |> Grid2D.put_many([
        {:start, AABB.from_circle(0, 0, 5), :players},
        {:middle, AABB.from_circle(100, 0, 5), :players},
        {:end, AABB.from_circle(200, 0, 5), :players},
        {:outside, AABB.from_circle(100, 100, 5), :players}
      ])

    assert Grid2D.query_swept_circle(grid, {-10, 0}, {210, 0}, 2, layers: :players) == [
             :end,
             :middle,
             :start
           ]
  end

  test "lists all indexed identifiers through optional layer filtering" do
    grid =
      Grid2D.new()
      |> Grid2D.put(:player, AABB.from_circle(0, 0, 10), layers: [:actors, :players])
      |> Grid2D.put(:projectile, AABB.from_circle(100, 0, 4), layers: :projectiles)
      |> Grid2D.put(:bot, AABB.from_circle(200, 0, 10), layers: [:actors, :bots])

    assert Grid2D.ids(grid) == [:bot, :player, :projectile]
    assert Grid2D.ids(grid, layers: :players) == [:player]
    assert Grid2D.ids(grid, layers: [:bots, :projectiles]) == [:bot, :projectile]
  end

  test "never drops an AABB intersection across deterministic random worlds" do
    :rand.seed(:exsss, {42, 43, 44})

    entries =
      Enum.map(1..200, fn id ->
        x = random_coordinate()
        y = random_coordinate()
        radius = 2 + :rand.uniform(30)
        {id, AABB.from_circle(x, y, radius), :actors}
      end)

    grid = Grid2D.put_many(Grid2D.new(cell_size: 64), entries)

    Enum.each(1..100, fn _query ->
      x = random_coordinate()
      y = random_coordinate()
      bounds = AABB.from_circle(x, y, 1 + :rand.uniform(200))

      expected =
        entries
        |> Enum.filter(fn {_id, entry_bounds, _layer} ->
          AABB.intersects?(entry_bounds, bounds)
        end)
        |> Enum.map(&elem(&1, 0))
        |> Enum.sort()

      assert Grid2D.query_aabb(grid, bounds, layers: :actors) == expected
    end)
  end

  defp random_coordinate(), do: :rand.uniform(4_000) - 2_000
end
