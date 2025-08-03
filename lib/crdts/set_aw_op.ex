defmodule Set_AW_OP do
  @behaviour CRDT

  @moduledoc """
  Documentation for `Set_AW_OP`.

  An operation-based Add-Wins Set CRDT.
  In add-wins semantics, concurrent add and remove operations for the same element
  result in the element being present in the set.

  Reference papers:
  Marc Shapiro, Nuno Preguiça, Carlos Baquero, Marek Zawirski (2011)
  A comprehensive study of Convergent and Commutative Replicated Data Types
  """

  @type t :: :set_aw_op
  @type internal_state :: %{elements: MapSet.t(), removed: MapSet.t()}

  def new() do
    %{elements: MapSet.new(), removed: MapSet.new()}
  end

  def value(state) do
    MapSet.difference(state.elements, state.removed) |> MapSet.to_list()
  end

  def downstream({:add, element}, _state) do
    {:ok, {:add, element}}
  end

  def downstream({:add_all, elements}, _state) when is_list(elements) do
    {:ok, {:add_all, elements}}
  end

  def downstream({:remove, element}, state) do
    case MapSet.member?(state.elements, element) do
      true -> {:ok, {:remove, element}}
      false -> {:ok, :noop}
    end
  end

  def downstream({:remove_all, elements}, state) when is_list(elements) do
    existing_elements = Enum.filter(elements, &MapSet.member?(state.elements, &1))
    case existing_elements do
      [] -> {:ok, :noop}
      _ -> {:ok, {:remove_all, existing_elements}}
    end
  end

  def downstream({:reset}, _state) do
    {:ok, {:reset}}
  end

  def update({:add, element}, state) do
    new_state = %{state | elements: MapSet.put(state.elements, element)}
    {:ok, new_state}
  end

  def update({:add_all, elements}, state) do
    new_elements = Enum.reduce(elements, state.elements, &MapSet.put(&2, &1))
    new_state = %{state | elements: new_elements}
    {:ok, new_state}
  end

  def update({:remove, element}, state) do
    new_state = %{state | removed: MapSet.put(state.removed, element)}
    {:ok, new_state}
  end

  def update({:remove_all, elements}, state) do
    new_removed = Enum.reduce(elements, state.removed, &MapSet.put(&2, &1))
    new_state = %{state | removed: new_removed}
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

  def require_state_downstream({:add, _}) do false end
  def require_state_downstream({:add_all, _}) do false end
  def require_state_downstream({:remove, _}) do true end
  def require_state_downstream({:remove_all, _}) do true end
  def require_state_downstream({:reset}) do false end

end