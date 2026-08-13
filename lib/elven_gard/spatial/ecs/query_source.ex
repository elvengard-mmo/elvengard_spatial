if Code.ensure_loaded?(ElvenGard.ECS.Query.Source) do
  defmodule ElvenGard.Spatial.ECS.QuerySource do
    @moduledoc """
    Adapts a partition-owned spatial index to `ElvenGard.ECS.Query.Source`.

    The source returns broad-phase entity IDs before the ECS loads components.
    Regular ECS component requirements and filters remain authoritative.
    """

    @behaviour ElvenGard.ECS.Query.Source

    alias ElvenGard.ECS.Entity
    alias ElvenGard.Spatial.AABB
    alias ElvenGard.Spatial.Grid2D.Server

    @enforce_keys [:server, :partition, :shape]
    defstruct [:server, :partition, :shape, opts: []]

    @type center :: {number(), number()}
    @type shape ::
            {:aabb, AABB.t()}
            | {:circle, center(), non_neg_integer() | float()}
            | {:swept_circle, center(), center(), non_neg_integer() | float()}

    @type t :: %__MODULE__{
            server: GenServer.server(),
            partition: Entity.partition(),
            shape: shape(),
            opts: Keyword.t()
          }

    ## Public API

    @spec aabb(GenServer.server(), Entity.partition(), AABB.t(), Keyword.t()) :: t()
    def aabb(server, partition, %AABB{} = bounds, opts \\ []) do
      %__MODULE__{server: server, partition: partition, shape: {:aabb, bounds}, opts: opts}
    end

    @spec circle(
            GenServer.server(),
            Entity.partition(),
            center(),
            non_neg_integer() | float(),
            Keyword.t()
          ) :: t()
    def circle(server, partition, center, radius, opts \\ []) do
      %__MODULE__{
        server: server,
        partition: partition,
        shape: {:circle, center, radius},
        opts: opts
      }
    end

    @spec swept_circle(
            GenServer.server(),
            Entity.partition(),
            center(),
            center(),
            non_neg_integer() | float(),
            Keyword.t()
          ) :: t()
    def swept_circle(server, partition, origin, destination, radius, opts \\ []) do
      %__MODULE__{
        server: server,
        partition: partition,
        shape: {:swept_circle, origin, destination, radius},
        opts: opts
      }
    end

    ## Query.Source callbacks

    @impl true
    def candidate_ids(%__MODULE__{} = source, query_partition) do
      validate_partition!(source.partition, query_partition)
      resolve_shape(source)
    end

    ## Private functions

    defp resolve_shape(%__MODULE__{} = source) do
      case source.shape do
        {:aabb, bounds} ->
          Server.query_aabb(source.server, bounds, source.opts)

        {:circle, center, radius} ->
          Server.query_circle(source.server, center, radius, source.opts)

        {:swept_circle, origin, destination, radius} ->
          Server.query_swept_circle(source.server, origin, destination, radius, source.opts)
      end
    end

    defp validate_partition!(source_partition, query_partition) do
      unless query_partition in [:any, source_partition] do
        raise ArgumentError,
              "spatial source belongs to #{inspect(source_partition)}, " <>
                "but the ECS query targets #{inspect(query_partition)}"
      end
    end
  end
end
