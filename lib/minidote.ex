defmodule Minidote do
  require Logger

  @moduledoc """
  Simple CRDT database API.
  """

  def start_link(server_name) do
    Minidote.Server.start_link(server_name)
  end

  def read_objects(objects, clock) do
    Logger.notice("#{node()}: read_objects(#{inspect(objects)}, #{inspect(clock)})")
    Minidote.Server.read_objects(objects, clock)
  end

  def update_objects(updates, clock) do
    Logger.notice("#{node()}: update_objects(#{inspect(updates)}, #{inspect(clock)})")
    Minidote.Server.update_objects(updates, clock)
  end
end
