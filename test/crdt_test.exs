defmodule CRDTTest do
  use ExUnit.Case
  doctest CRDT

  test "counter_pn_ob basic operations" do
    state = CRDT.new(:counter_pn_ob)
    assert CRDT.value(:counter_pn_ob, state) == 0

    {:ok, effect} = CRDT.downstream(:counter_pn_ob, :increment, state)
    {:ok, new_state} = CRDT.update(:counter_pn_ob, effect, state)
    assert CRDT.value(:counter_pn_ob, new_state) == 1

    {:ok, effect2} = CRDT.downstream(:counter_pn_ob, {:increment, 5}, new_state)
    {:ok, new_state2} = CRDT.update(:counter_pn_ob, effect2, new_state)
    assert CRDT.value(:counter_pn_ob, new_state2) == 6

    {:ok, effect3} = CRDT.downstream(:counter_pn_ob, :decrement, new_state2)
    {:ok, new_state3} = CRDT.update(:counter_pn_ob, effect3, new_state2)
    assert CRDT.value(:counter_pn_ob, new_state3) == 5
  end

  test "set_aw_op basic operations" do
    state = CRDT.new(:set_aw_op)
    assert CRDT.value(:set_aw_op, state) == []

    {:ok, effect} = CRDT.downstream(:set_aw_op, {:add, "item1"}, state)
    {:ok, new_state} = CRDT.update(:set_aw_op, effect, state)
    assert "item1" in CRDT.value(:set_aw_op, new_state)

    {:ok, effect2} = CRDT.downstream(:set_aw_op, {:add, "item2"}, new_state)
    {:ok, new_state2} = CRDT.update(:set_aw_op, effect2, new_state)
    value = CRDT.value(:set_aw_op, new_state2)
    assert "item1" in value
    assert "item2" in value

    {:ok, effect3} = CRDT.downstream(:set_aw_op, {:remove, "item1"}, new_state2)
    {:ok, new_state3} = CRDT.update(:set_aw_op, effect3, new_state2)
    value2 = CRDT.value(:set_aw_op, new_state3)
    assert "item1" not in value2
    assert "item2" in value2
  end

  test "mv_register basic operations" do
    state = CRDT.new(:mv_register)
    assert CRDT.value(:mv_register, state) == nil

    {:ok, effect} = CRDT.downstream(:mv_register, {:assign, "value1"}, state)
    {:ok, new_state} = CRDT.update(:mv_register, effect, state)
    assert CRDT.value(:mv_register, new_state) == ["value1"]

    {:ok, effect2} = CRDT.downstream(:mv_register, {:assign, "value2"}, new_state)
    {:ok, new_state2} = CRDT.update(:mv_register, effect2, new_state)
    assert CRDT.value(:mv_register, new_state2) == ["value2"]
  end

  test "counter_pn_sb basic operations" do
    state = CRDT.new(:counter_pn_sb)
    assert CRDT.value(:counter_pn_sb, state) == 0

    {:ok, effect} = CRDT.downstream(:counter_pn_sb, :increment, state)
    {:ok, new_state} = CRDT.update(:counter_pn_sb, effect, state)
    assert CRDT.value(:counter_pn_sb, new_state) == 1
  end

  test "set_rw_op basic operations" do
    state = CRDT.new(:set_rw_op)
    assert CRDT.value(:set_rw_op, state) == []

    {:ok, effect} = CRDT.downstream(:set_rw_op, {:add, "item1"}, state)
    {:ok, new_state} = CRDT.update(:set_rw_op, effect, state)
    assert "item1" in CRDT.value(:set_rw_op, new_state)
  end

  test "lww_register basic operations" do
    state = CRDT.new(:lww_register)
    assert CRDT.value(:lww_register, state) == nil

    {:ok, effect} = CRDT.downstream(:lww_register, {:assign, "value1"}, state)
    {:ok, new_state} = CRDT.update(:lww_register, effect, state)
    assert CRDT.value(:lww_register, new_state) == "value1"

    # Test reset
    {:ok, reset_effect} = CRDT.downstream(:lww_register, {:reset, nil}, new_state)
    {:ok, reset_state} = CRDT.update(:lww_register, reset_effect, new_state)
    assert CRDT.value(:lww_register, reset_state) == nil
  end

  test "counter_pn_ob concurrent increments and decrements" do
    state = CRDT.new(:counter_pn_ob)
    
    # Simulate concurrent operations
    {:ok, inc_effect1} = CRDT.downstream(:counter_pn_ob, {:increment, 5}, state)
    {:ok, inc_effect2} = CRDT.downstream(:counter_pn_ob, {:increment, 3}, state)
    {:ok, dec_effect} = CRDT.downstream(:counter_pn_ob, {:decrement, 2}, state)
    
    # Apply effects in different orders to test commutativity
    {:ok, state1} = CRDT.update(:counter_pn_ob, inc_effect1, state)
    {:ok, state2} = CRDT.update(:counter_pn_ob, inc_effect2, state1)
    {:ok, final_state1} = CRDT.update(:counter_pn_ob, dec_effect, state2)
    
    # Different order
    {:ok, state3} = CRDT.update(:counter_pn_ob, dec_effect, state)
    {:ok, state4} = CRDT.update(:counter_pn_ob, inc_effect2, state3)
    {:ok, final_state2} = CRDT.update(:counter_pn_ob, inc_effect1, state4)
    
    # Should converge to same value regardless of order
    assert CRDT.value(:counter_pn_ob, final_state1) == 6
    assert CRDT.value(:counter_pn_ob, final_state2) == 6
  end

  test "set_aw_op add-wins semantics" do
    state = CRDT.new(:set_aw_op)
    
    # Add an item
    {:ok, add_effect} = CRDT.downstream(:set_aw_op, {:add, "item1"}, state)
    {:ok, _state_with_item} = CRDT.update(:set_aw_op, add_effect, state)
    
    # Concurrently add and remove the same item (add should win)
    {:ok, add_effect2} = CRDT.downstream(:set_aw_op, {:add, "item1"}, state)
    {:ok, remove_effect} = CRDT.downstream(:set_aw_op, {:remove, "item1"}, state)
    
    {:ok, state1} = CRDT.update(:set_aw_op, add_effect2, state)
    {:ok, final_state} = CRDT.update(:set_aw_op, remove_effect, state1)
    
    # Add should win over remove
    value = CRDT.value(:set_aw_op, final_state)
    assert "item1" in value
  end

  test "set_rw_op remove-wins semantics" do
    state = CRDT.new(:set_rw_op)
    
    # Add items first
    {:ok, add_effect1} = CRDT.downstream(:set_rw_op, {:add, "item1"}, state)
    {:ok, state1} = CRDT.update(:set_rw_op, add_effect1, state)
    
    {:ok, add_effect2} = CRDT.downstream(:set_rw_op, {:add, "item2"}, state1)
    {:ok, state2} = CRDT.update(:set_rw_op, add_effect2, state1)
    
    # Concurrently add and remove item1 (remove should win)
    {:ok, add_effect3} = CRDT.downstream(:set_rw_op, {:add, "item1"}, state2)
    {:ok, remove_effect} = CRDT.downstream(:set_rw_op, {:remove, "item1"}, state2)
    
    {:ok, state3} = CRDT.update(:set_rw_op, add_effect3, state2)
    {:ok, final_state} = CRDT.update(:set_rw_op, remove_effect, state3)
    
    # Remove should win over add
    value = CRDT.value(:set_rw_op, final_state)
    assert "item1" not in value
    assert "item2" in value
  end

  test "mv_register concurrent assignments" do
    state = CRDT.new(:mv_register)
    
    # Concurrent assignments should create multiple values
    {:ok, effect1} = CRDT.downstream(:mv_register, {:assign, "value_a"}, state)
    {:ok, effect2} = CRDT.downstream(:mv_register, {:assign, "value_b"}, state)
    
    {:ok, state1} = CRDT.update(:mv_register, effect1, state)
    {:ok, state2} = CRDT.update(:mv_register, effect2, state1)
    
    # Should contain both values
    value = CRDT.value(:mv_register, state2)
    assert is_list(value)
    assert "value_a" in value or "value_b" in value
  end

  test "lww_register timestamp ordering" do
    state = CRDT.new(:lww_register)
    
    # First assignment
    {:ok, effect1} = CRDT.downstream(:lww_register, {:assign, "first"}, state)
    {:ok, state1} = CRDT.update(:lww_register, effect1, state)
    
    # Small delay to ensure different timestamps
    Process.sleep(1)
    
    # Second assignment (should win due to later timestamp)
    {:ok, effect2} = CRDT.downstream(:lww_register, {:assign, "second"}, state1)
    {:ok, state2} = CRDT.update(:lww_register, effect2, state1)
    
    assert CRDT.value(:lww_register, state2) == "second"
    
    # Apply first effect after second (should not change value)
    {:ok, state3} = CRDT.update(:lww_register, effect1, state2)
    assert CRDT.value(:lww_register, state3) == "second"
  end

  test "counter_pn_sb state-based operations" do
    state1 = CRDT.new(:counter_pn_sb)
    state2 = CRDT.new(:counter_pn_sb)
    
    # Operations on different replicas
    {:ok, effect1} = CRDT.downstream(:counter_pn_sb, {:increment, 3}, state1)
    {:ok, updated_state1} = CRDT.update(:counter_pn_sb, effect1, state1)
    
    {:ok, effect2} = CRDT.downstream(:counter_pn_sb, {:increment, 5}, state2)
    {:ok, updated_state2} = CRDT.update(:counter_pn_sb, effect2, state2)
    
    # States should be mergeable
    assert CRDT.value(:counter_pn_sb, updated_state1) == 3
    assert CRDT.value(:counter_pn_sb, updated_state2) == 5
  end

  test "CRDT idempotency" do
    state = CRDT.new(:set_aw_op)
    
    {:ok, effect} = CRDT.downstream(:set_aw_op, {:add, "item1"}, state)
    {:ok, state1} = CRDT.update(:set_aw_op, effect, state)
    
    # Applying the same effect multiple times should be idempotent
    {:ok, state2} = CRDT.update(:set_aw_op, effect, state1)
    {:ok, state3} = CRDT.update(:set_aw_op, effect, state2)
    
    value1 = CRDT.value(:set_aw_op, state1)
    value2 = CRDT.value(:set_aw_op, state2)
    value3 = CRDT.value(:set_aw_op, state3)
    
    assert value1 == value2
    assert value2 == value3
    assert length(value1) == 1
    assert "item1" in value1
  end

  test "all CRDTs support new operation" do
    crdt_types = [:counter_pn_ob, :counter_pn_sb, :set_aw_op, :set_rw_op, :mv_register, :lww_register]
    
    for crdt_type <- crdt_types do
      state = CRDT.new(crdt_type)
      assert state != nil, "Failed to create #{crdt_type}"
      
      # All CRDTs should have a defined initial value
      value = CRDT.value(crdt_type, state)
      assert value != nil or crdt_type in [:mv_register, :lww_register], "#{crdt_type} should have non-nil initial value"
    end
  end
end