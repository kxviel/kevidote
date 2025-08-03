defmodule Counter_PN_SB do
  @behaviour CRDT

  @moduledoc """
  Documentation for `Counter_PN_SB`.

  This is a convergent, replicated, state-based PN-Counter (Positive Negative Counter).
  State-based CRDTs synchronize by merging their full state, rather than propagating operations.
  
  The counter maintains separate increment/decrement values per node to ensure convergence.
  """

  @type t :: :counter_pn_sb
  @type internal_state :: %{pos: %{atom() => integer()}, neg: %{atom() => integer()}}

  def new() do
    %{pos: %{}, neg: %{}}
  end

  def value(state) do
    pos_sum = Map.values(state.pos) |> Enum.sum()
    neg_sum = Map.values(state.neg) |> Enum.sum()
    pos_sum - neg_sum
  end

  def downstream(:increment, _state) do
    {:ok, {:increment, node(), 1}}
  end

  def downstream(:decrement, _state) do
    {:ok, {:decrement, node(), 1}}
  end

  def downstream({:increment, amount}, _state) when is_integer(amount) do
    {:ok, {:increment, node(), amount}}
  end

  def downstream({:decrement, amount}, _state) when is_integer(amount) do
    {:ok, {:decrement, node(), amount}}
  end

  def update({:increment, node_id, amount}, state) do
    new_pos = Map.update(state.pos, node_id, amount, &(&1 + amount))
    {:ok, %{state | pos: new_pos}}
  end

  def update({:decrement, node_id, amount}, state) do
    new_neg = Map.update(state.neg, node_id, amount, &(&1 + amount))
    {:ok, %{state | neg: new_neg}}
  end

  def equal(state1, state2) do
    state1.pos == state2.pos && state1.neg == state2.neg
  end

  def require_state_downstream(_) do false end

  # State-based merge function for synchronization
  def merge(state1, state2) do
    merged_pos = Map.merge(state1.pos, state2.pos, fn _k, v1, v2 -> max(v1, v2) end)
    merged_neg = Map.merge(state1.neg, state2.neg, fn _k, v1, v2 -> max(v1, v2) end)
    %{pos: merged_pos, neg: merged_neg}
  end
end