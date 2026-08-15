defmodule ElvenGard.Spatial.InterestGraph.Delta do
  @moduledoc """
  Incremental membership transition returned by an interest-graph mutation.

  For an entity mutation, IDs identify observers. For an observer mutation,
  IDs identify visible entities. Lists use Erlang term ordering so consumers
  can replicate transitions deterministically.
  """

  @enforce_keys [:entered, :left, :current]
  defstruct [:entered, :left, :current]

  @type id :: any()
  @type t :: %__MODULE__{
          entered: [id()],
          left: [id()],
          current: [id()]
        }

  ## Public API

  @doc false
  @spec new(MapSet.t(id()), MapSet.t(id())) :: t()
  def new(previous, current) do
    %__MODULE__{
      entered: current |> MapSet.difference(previous) |> sorted(),
      left: previous |> MapSet.difference(current) |> sorted(),
      current: sorted(current)
    }
  end

  ## Private functions

  defp sorted(ids), do: ids |> MapSet.to_list() |> Enum.sort()
end
