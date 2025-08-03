defmodule Counter_PN_OB do
  @behaviour CRDT

  @moduledoc """
  Simple PN-Counter for increment/decrement operations.
  """

  def new do
    0
  end

  def value(counter_state) when is_integer(counter_state) do
    counter_state
  end

  def downstream(:increment, _state), do: {:ok, 1}
  def downstream(:decrement, _state), do: {:ok, -1}
  def downstream({:increment, amount}, _state) when is_integer(amount), do: {:ok, amount}
  def downstream({:decrement, amount}, _state) when is_integer(amount), do: {:ok, -amount}

  def update(effect, counter_state) when is_integer(effect) and is_integer(counter_state) do
    {:ok, counter_state + effect}
  end

  def equal(state1, state2), do: state1 === state2

  def require_state_downstream(_operation), do: false
end
