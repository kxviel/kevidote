defmodule MV_Register do
  @behaviour CRDT

  @moduledoc """
  Documentation for `MV_Register`.

  A Multi-Value Register CRDT (operation-based).
  When concurrent assignments occur, all concurrent values are preserved.
  This provides multi-value semantics where concurrent writes result in multiple values.

  This is an operation-based CRDT where each assignment includes a unique identifier
  and a timestamp to determine causality and resolve concurrent assignments.
  """

  @type t :: :mv_register
  @type internal_state :: %{values: %{term() => {term(), integer(), atom()}}}

  def new() do
    %{values: %{}}
  end

  def value(state) do
    case Map.values(state.values) do
      [] -> nil
      values -> Enum.map(values, fn {value, _timestamp, _node} -> value end)
    end
  end

  def downstream({:assign, value}, _state) do
    timestamp = :os.system_time(:microsecond)
    node_id = node()
    assignment_id = {timestamp, node_id, make_ref()}
    {:ok, {:assign, assignment_id, value}}
  end

  def downstream({:reset}, _state) do
    {:ok, {:reset}}
  end

  def update({:assign, assignment_id, value}, state) do
    {timestamp, node_id, _ref} = assignment_id
    
    new_values = Map.put(state.values, assignment_id, {value, timestamp, node_id})
    
    concurrent_values = Enum.filter(new_values, fn {_id, {_val, ts, _node}} ->
      not is_superseded_by?(ts, timestamp, new_values)
    end) |> Map.new()
    
    new_state = %{state | values: concurrent_values}
    {:ok, new_state}
  end

  def update({:reset}, _state) do
    {:ok, new()}
  end

  def equal(state1, state2) do
    state1.values == state2.values
  end

  def require_state_downstream({:assign, _}) do false end
  def require_state_downstream({:reset}) do false end

  defp is_superseded_by?(timestamp, other_timestamp, all_values) do
    timestamp < other_timestamp and 
    Enum.any?(all_values, fn {_id, {_val, ts, _node}} -> 
      ts == other_timestamp 
    end)
  end
end