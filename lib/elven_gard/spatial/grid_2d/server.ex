defmodule ElvenGard.Spatial.Grid2D.Server do
  @moduledoc """
  Owns one mutable `ElvenGard.Spatial.Grid2D` behind a serialized API.

  Writes and queries are synchronous so a query always observes either the
  complete grid before an update or the complete grid after it. This process is
  suitable for a derived spatial index owned by one game partition.
  """

  use GenServer

  alias ElvenGard.Spatial.{AABB, Grid2D}

  ## Public API

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    case name do
      nil -> GenServer.start_link(__MODULE__, opts)
      server_name -> GenServer.start_link(__MODULE__, opts, name: server_name)
    end
  end

  @spec size(GenServer.server()) :: non_neg_integer()
  def size(server), do: GenServer.call(server, :size)

  @spec put(GenServer.server(), Grid2D.id(), AABB.t(), Keyword.t()) :: :ok
  def put(server, id, %AABB{} = bounds, opts \\ []) do
    GenServer.call(server, {:put, id, bounds, opts})
  end

  @spec put_many(GenServer.server(), [Grid2D.put_entry()]) :: :ok
  def put_many(server, entries) when is_list(entries) do
    GenServer.call(server, {:put_many, entries})
  end

  @spec replace_all(GenServer.server(), [Grid2D.put_entry()]) :: :ok
  def replace_all(server, entries) when is_list(entries) do
    GenServer.call(server, {:replace_all, entries})
  end

  @spec delete(GenServer.server(), Grid2D.id()) :: :ok
  def delete(server, id) do
    GenServer.call(server, {:delete, id})
  end

  @spec query_aabb(GenServer.server(), AABB.t(), Keyword.t()) :: [Grid2D.id()]
  def query_aabb(server, %AABB{} = bounds, opts \\ []) do
    GenServer.call(server, {:query_aabb, bounds, opts})
  end

  @spec query_circle(
          GenServer.server(),
          {number(), number()},
          non_neg_integer() | float(),
          Keyword.t()
        ) :: [Grid2D.id()]
  def query_circle(server, center, radius, opts \\ []) do
    GenServer.call(server, {:query_circle, center, radius, opts})
  end

  @spec query_swept_circle(
          GenServer.server(),
          {number(), number()},
          {number(), number()},
          non_neg_integer() | float(),
          Keyword.t()
        ) :: [Grid2D.id()]
  def query_swept_circle(server, origin, destination, radius, opts \\ []) do
    GenServer.call(server, {:query_swept_circle, origin, destination, radius, opts})
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    {:ok, Grid2D.new(opts)}
  end

  @impl true
  def handle_call(:size, _from, grid) do
    {:reply, Grid2D.size(grid), grid}
  end

  def handle_call({:put, id, bounds, opts}, _from, grid) do
    {:reply, :ok, Grid2D.put(grid, id, bounds, opts)}
  end

  def handle_call({:put_many, entries}, _from, grid) do
    {:reply, :ok, Grid2D.put_many(grid, entries)}
  end

  def handle_call({:replace_all, entries}, _from, grid) do
    new_grid = Grid2D.put_many(Grid2D.new(cell_size: grid.cell_size), entries)
    {:reply, :ok, new_grid}
  end

  def handle_call({:delete, id}, _from, grid) do
    {:reply, :ok, Grid2D.delete(grid, id)}
  end

  def handle_call({:query_aabb, bounds, opts}, _from, grid) do
    {:reply, Grid2D.query_aabb(grid, bounds, opts), grid}
  end

  def handle_call({:query_circle, center, radius, opts}, _from, grid) do
    {:reply, Grid2D.query_circle(grid, center, radius, opts), grid}
  end

  def handle_call({:query_swept_circle, origin, destination, radius, opts}, _from, grid) do
    result = Grid2D.query_swept_circle(grid, origin, destination, radius, opts)
    {:reply, result, grid}
  end
end
