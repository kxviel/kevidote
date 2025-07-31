defmodule LWW_Register do
  @behaviour CRDT

  @moduledoc """
  Documentation for `LWW_Register`.

  This is a Last-Writer-Wins Register CRDT (operation-based).
  In case of concurrent writes, the operation with the higher timestamp wins.
  Each write operation includes a timestamp and node identifier for tie-breaking.
  
  Internal state: {value, timestamp, node}
  Operations:
  - {:assign, value} - assigns a new value with current timestamp
  - {:reset} - resets to initial state
  """

  @type t :: :lww_register

  def new() do
    {nil, 0, nil}
  end

  def value({val, _timestamp, _node}) do
    val
  end

  def downstream({:assign, val}, _state) do
    timestamp = :os.system_time(:microsecond)
    node = node()
    {:ok, {:assign, val, timestamp, node}}
  end

  def downstream({:reset, _args}, _state) do
    {:ok, {:reset}}
  end

  def update({:assign, val, timestamp, node}, {current_val, current_ts, current_node}) do
    if timestamp > current_ts or (timestamp == current_ts and node > current_node) do
      {:ok, {val, timestamp, node}}
    else
      {:ok, {current_val, current_ts, current_node}}
    end
  end

  def update({:reset}, _state) do
    {:ok, {nil, 0, nil}}
  end

  def equal({val1, ts1, node1}, {val2, ts2, node2}) do
    val1 === val2 and ts1 === ts2 and node1 === node2
  end

  def require_state_downstream(_) do false end
end