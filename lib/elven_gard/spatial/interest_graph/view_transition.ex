defmodule ElvenGard.Spatial.InterestGraph.ViewTransition do
  @moduledoc """
  Allocation-light observer membership before and after one atomic graph step.

  `previous` is `nil` when the observer did not exist before the step. This lets
  consumers distinguish a new observer from an existing observer whose prior
  view happened to be empty without retaining their own graph history.
  """

  @enforce_keys [:previous, :current]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          previous: MapSet.t(any()) | nil,
          current: MapSet.t(any())
        }
end
