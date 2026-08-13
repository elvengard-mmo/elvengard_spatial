defmodule ElvenGard.Spatial.TestPosition do
  @moduledoc false

  use ElvenGard.ECS.Component, state: [x: 0.0, y: 0.0, radius: 10.0]
end
