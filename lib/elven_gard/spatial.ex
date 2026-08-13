defmodule ElvenGard.Spatial do
  @moduledoc """
  Deterministic spatial broad-phase primitives for real-time Elixir games.

  `ElvenGard.Spatial` deliberately knows nothing about ECS components, physics
  responses, or gameplay rules. Games insert opaque entity identifiers and
  axis-aligned bounds into an index, use the index to select nearby candidates,
  then run their own exact collision tests on that reduced candidate set.
  """
end
