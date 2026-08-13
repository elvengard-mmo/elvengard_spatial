if Code.ensure_loaded?(ElvenGard.ECS.ChangeSet) do
  defmodule ElvenGard.Spatial.ECS.Indexer do
    @moduledoc """
    Applies one committed ECS change set to a spatial index incrementally.

    The indexed component must be single-valued per entity. A projector converts
    that component into spatial bounds and layers, returns `:ignore` to remove
    the entity from the index, or returns `:skip` when the change cannot affect
    this index. All resulting mutations are applied to the index server in one
    serialized call.
    """

    alias ElvenGard.ECS.{ChangeSet, Component, Entity, Query}
    alias ElvenGard.Spatial.AABB
    alias ElvenGard.Spatial.Grid2D.Server

    @type projection :: :ignore | :skip | {AABB.t(), atom() | [atom()]}
    @type projector :: (Entity.t(), Component.t() -> projection())
    @type operation :: :delete | {:put, AABB.t(), atom() | [atom()]}

    ## Public API

    @spec sync(GenServer.server(), ChangeSet.t(), module(), projector(), Keyword.t()) :: :ok
    def sync(server, change_set, component_module, projector, opts \\ [])
        when is_atom(component_module) and is_function(projector, 2) do
      partition = Keyword.get(opts, :partition)

      operations =
        change_set
        |> ChangeSet.to_list()
        |> Enum.reduce(%{}, fn {_name, change}, operations ->
          reduce_change(change, operations, component_module, projector, partition)
        end)

      {put_entries, deleted_ids} = materialize_operations(operations)
      Server.apply_changes(server, put_entries, deleted_ids)
    end

    ## Private functions

    defp reduce_change(
           {:spawn_entity, entity, components},
           operations,
           component_module,
           projector,
           _partition
         ) do
      case Enum.filter(components, &is_struct(&1, component_module)) do
        [] ->
          operations

        [component] ->
          put_projection(operations, entity, component, projector)

        components ->
          raise ArgumentError,
                "spatially indexed component #{inspect(component_module)} must be single-valued, " <>
                  "got #{length(components)} values for #{inspect(entity.id)}"
      end
    end

    defp reduce_change(
           {:despawn_entity, entity, _components},
           operations,
           _component_module,
           _projector,
           _partition
         ) do
      Map.put(operations, entity.id, :delete)
    end

    defp reduce_change(
           {operation, entity, component},
           operations,
           component_module,
           projector,
           _partition
         )
         when operation in [:add_component, :replace_component, :update_component] do
      case is_struct(component, component_module) do
        true -> put_projection(operations, entity, component, projector)
        false -> operations
      end
    end

    defp reduce_change(
           {:delete_component, entity, component},
           operations,
           component_module,
           _projector,
           _partition
         ) do
      case indexed_component?(component, component_module) do
        true -> Map.put(operations, entity.id, :delete)
        false -> operations
      end
    end

    defp reduce_change(
           {:set_partition, entity, new_partition},
           operations,
           component_module,
           projector,
           partition
         ) do
      case partition do
        nil ->
          operations

        ^new_partition ->
          case Query.fetch_component(entity, component_module) do
            {:ok, component} -> put_projection(operations, entity, component, projector)
            {:error, :not_found} -> Map.put(operations, entity.id, :delete)
          end

        _other_partition ->
          Map.put(operations, entity.id, :delete)
      end
    end

    defp reduce_change(_change, operations, _component_module, _projector, _partition),
      do: operations

    defp put_projection(operations, entity, component, projector) do
      case projector.(entity, component) do
        :skip ->
          operations

        :ignore ->
          Map.put(operations, entity.id, :delete)

        {%AABB{} = bounds, layers} when is_atom(layers) or is_list(layers) ->
          Map.put(operations, entity.id, {:put, bounds, layers})

        invalid ->
          raise ArgumentError,
                "spatial projector returned invalid projection for #{inspect(entity.id)}: " <>
                  inspect(invalid)
      end
    end

    defp indexed_component?(component, component_module) do
      case component do
        ^component_module -> true
        %^component_module{} -> true
        _other -> false
      end
    end

    defp materialize_operations(operations) do
      operations
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.reduce({[], []}, fn
        {entity_id, {:put, bounds, layers}}, {put_entries, deleted_ids} ->
          {[{entity_id, bounds, layers} | put_entries], deleted_ids}

        {entity_id, :delete}, {put_entries, deleted_ids} ->
          {put_entries, [entity_id | deleted_ids]}
      end)
    end
  end
end
