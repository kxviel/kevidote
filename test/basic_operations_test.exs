defmodule BasicOperationsTest do
  use ExUnit.Case

  test "counter starts at zero" do
    state = CRDT.new(:counter_pn_ob)
    assert CRDT.value(:counter_pn_ob, state) == 0
  end

  test "counter can be incremented by one" do
    state = CRDT.new(:counter_pn_ob)
    {:ok, effect} = CRDT.downstream(:counter_pn_ob, :increment, state)
    {:ok, new_state} = CRDT.update(:counter_pn_ob, effect, state)
    assert CRDT.value(:counter_pn_ob, new_state) == 1
  end

  test "empty set has no items" do
    state = CRDT.new(:set_aw_op)
    assert CRDT.value(:set_aw_op, state) == []
  end

  test "can add item to set" do
    state = CRDT.new(:set_aw_op)
    {:ok, effect} = CRDT.downstream(:set_aw_op, {:add, "apple"}, state)
    {:ok, new_state} = CRDT.update(:set_aw_op, effect, state)
    value = CRDT.value(:set_aw_op, new_state)
    assert "apple" in value
  end

  test "register starts empty" do
    state = CRDT.new(:mv_register)
    assert CRDT.value(:mv_register, state) == nil
  end
end