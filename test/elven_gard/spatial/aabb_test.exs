defmodule ElvenGard.Spatial.AABBTest do
  use ExUnit.Case, async: true

  alias ElvenGard.Spatial.AABB

  test "builds circle and swept-circle bounds" do
    assert AABB.from_circle(10, 20, 3) == AABB.new(7, 17, 13, 23)
    assert AABB.swept_circle({10, 20}, {-5, 30}, 2) == AABB.new(-7, 18, 12, 32)
  end

  test "detects overlap including touching edges" do
    bounds = AABB.new(-10, -10, 10, 10)

    assert AABB.intersects?(bounds, AABB.new(10, 0, 20, 2))
    refute AABB.intersects?(bounds, AABB.new(10.1, 0, 20, 2))
  end

  test "rejects inverted bounds" do
    assert_raise FunctionClauseError, fn -> AABB.new(10, 0, -10, 20) end
  end
end
