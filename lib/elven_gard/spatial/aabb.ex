defmodule ElvenGard.Spatial.AABB do
  @moduledoc """
  Two-dimensional axis-aligned bounds used by broad-phase queries.
  """

  @enforce_keys [:min_x, :min_y, :max_x, :max_y]
  defstruct [:min_x, :min_y, :max_x, :max_y]

  @type t :: %__MODULE__{
          min_x: number(),
          min_y: number(),
          max_x: number(),
          max_y: number()
        }

  ## Public API

  @spec new(number(), number(), number(), number()) :: t()
  def new(min_x, min_y, max_x, max_y)
      when is_number(min_x) and is_number(min_y) and is_number(max_x) and is_number(max_y) and
             min_x <= max_x and min_y <= max_y do
    %__MODULE__{min_x: min_x, min_y: min_y, max_x: max_x, max_y: max_y}
  end

  @spec from_circle(number(), number(), non_neg_integer() | float()) :: t()
  def from_circle(x, y, radius)
      when is_number(x) and is_number(y) and is_number(radius) and radius >= 0 do
    new(x - radius, y - radius, x + radius, y + radius)
  end

  @spec swept_circle(
          {number(), number()},
          {number(), number()},
          non_neg_integer() | float()
        ) :: t()
  def swept_circle({origin_x, origin_y}, {destination_x, destination_y}, radius)
      when is_number(origin_x) and is_number(origin_y) and is_number(destination_x) and
             is_number(destination_y) and is_number(radius) and radius >= 0 do
    new(
      min(origin_x, destination_x) - radius,
      min(origin_y, destination_y) - radius,
      max(origin_x, destination_x) + radius,
      max(origin_y, destination_y) + radius
    )
  end

  @spec intersects?(t(), t()) :: boolean()
  def intersects?(%__MODULE__{} = left, %__MODULE__{} = right) do
    left.min_x <= right.max_x and left.max_x >= right.min_x and
      left.min_y <= right.max_y and left.max_y >= right.min_y
  end
end
