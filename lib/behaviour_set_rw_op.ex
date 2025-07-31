defmodule Set_RW_OP do
  @behaviour CRDT

  @moduledoc """
  Documentation for `Set_RW_OP`.

  An operation-based Remove-Wins Set CRDT.
  In remove-wins semantics, concurrent add and remove operations for the same element
  result in the element being absent from the set (remove wins).

  This is the dual of the Add-Wins set, providing different conflict resolution semantics.
  """

  @type t :: :set_rw_op
  @type internal_state :: %{elements: MapSet.t(), removed: MapSet.t()}

  def new() do
    %{elements: MapSet.new(), removed: MapSet.new()}
  end

  def value(state) do
    MapSet.difference(state.elements, state.removed) |> MapSet.to_list()
  end

  def downstream({:add, element}, state) do
    # In remove-wins, we can only add if the element was never removed
    case MapSet.member?(state.removed, element) do
      true -> {:ok, :noop}
      false -> {:ok, {:add, element}}
    end
  end

  def downstream({:add_all, elements}, state) when is_list(elements) do
    valid_elements = Enum.filter(elements, &(not MapSet.member?(state.removed, &1)))
    case valid_elements do
      [] -> {:ok, :noop}
      _ -> {:ok, {:add_all, valid_elements}}
    end
  end

  def downstream({:remove, element}, _state) do
    {:ok, {:remove, element}}
  end

  def downstream({:remove_all, elements}, _state) when is_list(elements) do
    {:ok, {:remove_all, elements}}
  end

  def downstream({:reset}, _state) do
    {:ok, {:reset}}
  end

  def update({:add, element}, state) do
    # Only add if not in removed set
    case MapSet.member?(state.removed, element) do
      true -> {:ok, state}
      false -> 
        new_state = %{state | elements: MapSet.put(state.elements, element)}
        {:ok, new_state}
    end
  end

  def update({:add_all, elements}, state) do
    new_elements = Enum.reduce(elements, state.elements, fn element, acc ->
      case MapSet.member?(state.removed, element) do
        true -> acc
        false -> MapSet.put(acc, element)
      end
    end)
    new_state = %{state | elements: new_elements}
    {:ok, new_state}
  end

  def update({:remove, element}, state) do
    new_state = %{
      state | 
      elements: MapSet.delete(state.elements, element),
      removed: MapSet.put(state.removed, element)
    }
    {:ok, new_state}
  end

  def update({:remove_all, elements}, state) do
    new_elements = Enum.reduce(elements, state.elements, &MapSet.delete(&2, &1))
    new_removed = Enum.reduce(elements, state.removed, &MapSet.put(&2, &1))
    new_state = %{state | elements: new_elements, removed: new_removed}
    {:ok, new_state}
  end

  def update({:reset}, _state) do
    {:ok, new()}
  end

  def update(:noop, state) do
    {:ok, state}
  end

  def equal(state1, state2) do
    state1.elements == state2.elements && state1.removed == state2.removed
  end

  def require_state_downstream({:add, _}) do true end
  def require_state_downstream({:add_all, _}) do true end
  def require_state_downstream({:remove, _}) do false end
  def require_state_downstream({:remove_all, _}) do false end
  def require_state_downstream({:reset}) do false end
end