defmodule Minidote do
  require Logger

  @moduledoc """
  Documentation for `Minidote`.
  This is the API file for your Minidote
  Feel free to modify this and all other files of the template to your hearts content.
  """

  # ToDo: Improve type spec

  @type key :: {binary(), CRDT.t(), binary()}
  @type clock :: %{atom() => integer()} # vector clock

  def start_link(server_name) do
    # if you need arguments for initialization, change here
    Minidote.Server.start_link(server_name)
  end

  @spec read_objects([key()], clock() | :ignore) :: {:ok, [{key(), CRDT.value()}], clock()} | {:error, any()}
  def read_objects(objects, clock) do
    Logger.notice("#{node()}: read_objects(#{inspect objects}, #{inspect clock})")
    Minidote.Server.read_objects(objects, clock)
  end

  @spec update_objects([{key(), atom(), any()}], clock() | :ignore) :: {:ok, clock()} | {:error, any()}
  def update_objects(updates, clock) do
    Logger.notice("#{node()}: update_objects(#{inspect updates}, #{inspect clock})")
    Minidote.Server.update_objects(updates, clock)
  end

end
