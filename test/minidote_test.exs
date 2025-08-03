defmodule MinidoteTest do
  use ExUnit.Case
  doctest Minidote

  setup do
    # Clean up any existing state
    case Process.whereis(Minidote.Server) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
    
    case Process.whereis(PersistenceManager) do
      nil -> :ok
      pid -> GenServer.stop(pid) 
    end

    # Clean up persistent files
    node_name = Atom.to_string(node())
    state_file = "minidote_snapshot_#{node_name}.dets"
    log_file = "minidote_log_#{node_name}.dets"
    File.rm(state_file)
    File.rm(log_file)

    # Start the application components
    {:ok, _} = PersistenceManager.start_link()
    {:ok, _} = Minidote.Server.start_link(Minidote.Server)
    
    # Give processes time to initialize
    Process.sleep(100)
    
    :ok
  end

  test "basic counter operations" do
    key = {"test_counter", :counter_pn_ob, "test_bucket"}
    
    # Test increment
    {:ok, clock1} = Minidote.update_objects([{key, :increment, 5}], :ignore)
    assert is_map(clock1)
    
    # Test read
    {:ok, results, clock2} = Minidote.read_objects([key], :ignore)
    assert length(results) == 1
    [{{"test_counter", :counter_pn_ob, "test_bucket"}, value}] = results
    assert value == 5
    assert is_map(clock2)
    
    # Test decrement with session guarantee
    {:ok, clock3} = Minidote.update_objects([{key, :decrement, 2}], clock2)
    
    # Read with session guarantee
    {:ok, results2, _clock4} = Minidote.read_objects([key], clock3)
    [{{"test_counter", :counter_pn_ob, "test_bucket"}, value2}] = results2
    assert value2 == 3
  end

  test "basic set operations" do
    key = {"test_set", :set_aw_op, "test_bucket"}
    
    # Test add
    {:ok, clock1} = Minidote.update_objects([{key, :add, "item1"}], :ignore)
    
    # Test read
    {:ok, results, _clock2} = Minidote.read_objects([key], clock1)
    [{{"test_set", :set_aw_op, "test_bucket"}, value}] = results
    assert "item1" in value
    
    # Test add multiple items
    {:ok, clock3} = Minidote.update_objects([
      {key, :add, "item2"},
      {key, :add, "item3"}
    ], clock1)
    
    {:ok, results2, _clock4} = Minidote.read_objects([key], clock3)
    [{{"test_set", :set_aw_op, "test_bucket"}, value2}] = results2
    assert "item1" in value2
    assert "item2" in value2
    assert "item3" in value2
    
    # Test remove
    {:ok, clock5} = Minidote.update_objects([{key, :remove, "item2"}], clock3)
    
    {:ok, results3, _clock6} = Minidote.read_objects([key], clock5)
    [{{"test_set", :set_aw_op, "test_bucket"}, value3}] = results3
    assert "item1" in value3
    assert "item2" not in value3
    assert "item3" in value3
  end

  test "multi-value register operations" do
    key = {"test_register", :mv_register, "test_bucket"}
    
    # Test assign
    {:ok, clock1} = Minidote.update_objects([{key, :assign, "value1"}], :ignore)
    
    # Test read
    {:ok, results, _clock2} = Minidote.read_objects([key], clock1)
    [{{"test_register", :mv_register, "test_bucket"}, value}] = results
    assert value == ["value1"]
    
    # Test reassign
    {:ok, clock3} = Minidote.update_objects([{key, :assign, "value2"}], clock1)
    
    {:ok, results2, _clock4} = Minidote.read_objects([key], clock3)
    [{{"test_register", :mv_register, "test_bucket"}, value2}] = results2
    assert value2 == ["value2"]
  end

  test "lww register operations" do
    key = {"test_lww", :lww_register, "test_bucket"}
    
    # Test assign
    {:ok, clock1} = Minidote.update_objects([{key, :assign, "first_value"}], :ignore)
    
    # Test read
    {:ok, results, _clock2} = Minidote.read_objects([key], clock1)
    [{{"test_lww", :lww_register, "test_bucket"}, value}] = results
    assert value == "first_value"
    
    # Test reassign (should overwrite)
    {:ok, clock3} = Minidote.update_objects([{key, :assign, "second_value"}], clock1)
    
    {:ok, results2, _clock4} = Minidote.read_objects([key], clock3)
    [{{"test_lww", :lww_register, "test_bucket"}, value2}] = results2
    assert value2 == "second_value"
    
    # Test reset
    {:ok, clock5} = Minidote.update_objects([{key, :reset, nil}], clock3)
    
    {:ok, results3, _clock6} = Minidote.read_objects([key], clock5)
    [{{"test_lww", :lww_register, "test_bucket"}, value3}] = results3
    assert value3 == nil
  end

  test "concurrent counter operations with session guarantees" do
    key = {"concurrent_counter", :counter_pn_ob, "test_bucket"}
    
    # Initial update
    {:ok, clock1} = Minidote.update_objects([{key, :increment, 10}], :ignore)
    
    # Concurrent updates with session guarantees
    {:ok, clock2} = Minidote.update_objects([{key, :increment, 5}], clock1)
    {:ok, clock3} = Minidote.update_objects([{key, :decrement, 3}], clock1)
    
    # Merge clocks to ensure we see both updates
    merged_clock = merge_test_clocks(clock2, clock3)
    
    # Read with merged clock
    {:ok, results, _final_clock} = Minidote.read_objects([key], merged_clock)
    [{{"concurrent_counter", :counter_pn_ob, "test_bucket"}, value}] = results
    assert value == 12  # 10 + 5 - 3
  end

  test "mixed CRDT operations in single transaction" do
    counter_key = {"mixed_counter", :counter_pn_ob, "bucket1"}
    set_key = {"mixed_set", :set_aw_op, "bucket1"}
    register_key = {"mixed_register", :mv_register, "bucket1"}
    
    # Batch update multiple CRDTs
    {:ok, clock1} = Minidote.update_objects([
      {counter_key, :increment, 5},
      {set_key, :add, "item1"},
      {register_key, :assign, "value1"}
    ], :ignore)
    
    # Read all objects
    {:ok, results, _clock2} = Minidote.read_objects([counter_key, set_key, register_key], clock1)
    
    assert length(results) == 3
    
    counter_result = Enum.find(results, fn {{name, _, _}, _} -> name == "mixed_counter" end)
    set_result = Enum.find(results, fn {{name, _, _}, _} -> name == "mixed_set" end)
    register_result = Enum.find(results, fn {{name, _, _}, _} -> name == "mixed_register" end)
    
    {_, counter_value} = counter_result
    {_, set_value} = set_result  
    {_, register_value} = register_result
    
    assert counter_value == 5
    assert "item1" in set_value
    assert register_value == ["value1"]
  end

  test "set remove-wins operations" do
    key = {"test_set_rw", :set_rw_op, "test_bucket"}
    
    # Add items
    {:ok, clock1} = Minidote.update_objects([
      {key, :add, "item1"},
      {key, :add, "item2"},
      {key, :add, "item3"}
    ], :ignore)
    
    # Verify items are added
    {:ok, results, _clock2} = Minidote.read_objects([key], clock1)
    [{{"test_set_rw", :set_rw_op, "test_bucket"}, value}] = results
    assert "item1" in value
    assert "item2" in value
    assert "item3" in value
    
    # Remove some items
    {:ok, clock3} = Minidote.update_objects([
      {key, :remove, "item1"},
      {key, :remove, "item3"}
    ], clock1)
    
    # Verify removal
    {:ok, results2, _clock4} = Minidote.read_objects([key], clock3)
    [{{"test_set_rw", :set_rw_op, "test_bucket"}, value2}] = results2
    assert "item1" not in value2
    assert "item2" in value2
    assert "item3" not in value2
  end

  test "counter pn_sb (state-based) operations" do
    key = {"test_counter_sb", :counter_pn_sb, "test_bucket"}
    
    # Test increment
    {:ok, clock1} = Minidote.update_objects([{key, :increment, 7}], :ignore)
    
    # Test read
    {:ok, results, _clock2} = Minidote.read_objects([key], clock1)
    [{{"test_counter_sb", :counter_pn_sb, "test_bucket"}, value}] = results
    assert value == 7
    
    # Test decrement
    {:ok, clock3} = Minidote.update_objects([{key, :decrement, 2}], clock1)
    
    {:ok, results2, _clock4} = Minidote.read_objects([key], clock3)
    [{{"test_counter_sb", :counter_pn_sb, "test_bucket"}, value2}] = results2
    assert value2 == 5
  end

  test "session guarantees with read-your-writes" do
    key = {"session_test", :counter_pn_ob, "test_bucket"}
    
    # Write operation
    {:ok, write_clock} = Minidote.update_objects([{key, :increment, 10}], :ignore)
    
    # Read with session guarantee (should see own write)
    {:ok, results, read_clock} = Minidote.read_objects([key], write_clock)
    [{{"session_test", :counter_pn_ob, "test_bucket"}, value}] = results
    assert value == 10
    
    # Another write with session guarantee
    {:ok, write_clock2} = Minidote.update_objects([{key, :increment, 5}], read_clock)
    
    # Read should see both writes
    {:ok, results2, _final_clock} = Minidote.read_objects([key], write_clock2)
    [{{"session_test", :counter_pn_ob, "test_bucket"}, value2}] = results2
    assert value2 == 15
  end

  test "empty CRDT initial values" do
    counter_key = {"empty_counter", :counter_pn_ob, "test_bucket"}
    set_key = {"empty_set", :set_aw_op, "test_bucket"}
    register_key = {"empty_register", :mv_register, "test_bucket"}
    lww_key = {"empty_lww", :lww_register, "test_bucket"}
    
    # Read non-existent objects
    {:ok, results, _clock} = Minidote.read_objects([counter_key, set_key, register_key, lww_key], :ignore)
    
    assert length(results) == 4
    
    counter_result = Enum.find(results, fn {{name, _, _}, _} -> name == "empty_counter" end)
    set_result = Enum.find(results, fn {{name, _, _}, _} -> name == "empty_set" end)
    register_result = Enum.find(results, fn {{name, _, _}, _} -> name == "empty_register" end)
    lww_result = Enum.find(results, fn {{name, _, _}, _} -> name == "empty_lww" end)
    
    {_, counter_value} = counter_result
    {_, set_value} = set_result
    {_, register_value} = register_result
    {_, lww_value} = lww_result
    
    assert counter_value == 0
    assert set_value == []
    assert register_value == nil
    assert lww_value == nil
  end

  # Helper function to merge vector clocks for testing
  defp merge_test_clocks(clock1, clock2) do
    all_nodes = MapSet.union(MapSet.new(Map.keys(clock1)), MapSet.new(Map.keys(clock2)))
    
    Enum.reduce(all_nodes, %{}, fn node, acc ->
      val1 = Map.get(clock1, node, 0)
      val2 = Map.get(clock2, node, 0)
      Map.put(acc, node, max(val1, val2))
    end)
  end
end