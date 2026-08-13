defmodule ElvenGard.Spatial.Grid2D.Entry do
  @moduledoc false

  alias ElvenGard.Spatial.AABB

  @enforce_keys [:bounds, :layers, :cells]
  defstruct [:bounds, :layers, :cells]

  @type cell :: {integer(), integer()}
  @type t :: %__MODULE__{
          bounds: AABB.t(),
          layers: MapSet.t(atom()),
          cells: [cell()]
        }
end
