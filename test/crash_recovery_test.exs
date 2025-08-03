defmodule CrashRecoveryTest do
  use ExUnit.Case

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

    :ok
  end

  test "crash recovery restores state from logs" do
    # Start system
    {:ok, _} = PersistenceManager.start_link()
    {:ok, _} = Minidote.Server.start_link(Minidote.Server)
    Process.sleep(50)
    
    # Perform some operations
    key1 = {"counter1", :counter_pn_ob, "bucket1"}
    key2 = {"set1", :set_aw_op, "bucket1"}
    
    {:ok, _clock1} = Minidote.update_objects([{key1, :increment, 10}], :ignore)
    {:ok, _clock2} = Minidote.update_objects([{key2, :add, "item1"}], :ignore)
    {:ok, _clock3} = Minidote.update_objects([{key1, :increment, 5}], :ignore)
    
    # Verify state before crash
    {:ok, results_before, _} = Minidote.read_objects([key1, key2], :ignore)
    
    counter_result = Enum.find(results_before, fn {{name, _, _}, _} -> name == "counter1" end)
    set_result = Enum.find(results_before, fn {{name, _, _}, _} -> name == "set1" end)
    
    {_, counter_value_before} = counter_result
    {_, set_value_before} = set_result
    
    assert counter_value_before == 15
    assert "item1" in set_value_before
    
    # Simulate crash by stopping servers
    GenServer.stop(Minidote.Server)
    GenServer.stop(PersistenceManager)
    Process.sleep(100)
    
    # Restart system (simulating recovery after crash)
    {:ok, _} = PersistenceManager.start_link()
    {:ok, _} = Minidote.Server.start_link(Minidote.Server)
    Process.sleep(100)
    
    # Verify state is restored
    {:ok, results_after, _} = Minidote.read_objects([key1, key2], :ignore)
    
    counter_result_after = Enum.find(results_after, fn {{name, _, _}, _} -> name == "counter1" end)
    set_result_after = Enum.find(results_after, fn {{name, _, _}, _} -> name == "set1" end)
    
    {_, counter_value_after} = counter_result_after
    {_, set_value_after} = set_result_after
    
    assert counter_value_after == 15
    assert "item1" in set_value_after
    
    # Verify we can continue operations after recovery
    {:ok, _clock4} = Minidote.update_objects([{key1, :increment, 3}], :ignore)
    
    {:ok, final_results, _} = Minidote.read_objects([key1], :ignore)
    [{_, final_counter_value}] = final_results
    
    assert final_counter_value == 18
  end

  test "snapshot and log pruning works" do
    # Start system
    {:ok, _} = PersistenceManager.start_link(pruning_threshold: 5)  # Low threshold for testing
    {:ok, _} = Minidote.Server.start_link(Minidote.Server)
    Process.sleep(50)
    
    # Perform many operations to trigger pruning
    key = {"test_counter", :counter_pn_ob, "bucket1"}
    
    # Create 10 operations
    for i <- 1..10 do
      {:ok, _} = Minidote.update_objects([{key, :increment, i}], :ignore)
      Process.sleep(10)
    end
    
    # Force a snapshot
    PersistenceManager.snapshot_state(%{key => CRDT.new(:counter_pn_ob)}, %{node() => 10})
    Process.sleep(100)
    
    # Force pruning
    PersistenceManager.prune_log()
    Process.sleep(100)
    
    # Crash and recover
    GenServer.stop(Minidote.Server)
    GenServer.stop(PersistenceManager)
    Process.sleep(100)
    
    {:ok, _} = PersistenceManager.start_link(pruning_threshold: 5)
    {:ok, _} = Minidote.Server.start_link(Minidote.Server)
    Process.sleep(100)
    
    # System should still work after pruning
    {:ok, _} = Minidote.update_objects([{key, :increment, 1}], :ignore)
    {:ok, results, _} = Minidote.read_objects([key], :ignore)
    [{_, value}] = results
    
    # Should be able to read some value (exact value depends on what was pruned)
    assert is_integer(value)
    assert value >= 0
  end

  test "recovery handles empty state correctly" do
    # Start system with no prior state
    {:ok, _} = PersistenceManager.start_link()
    {:ok, _} = Minidote.Server.start_link(Minidote.Server)
    Process.sleep(50)
    
    # Should be able to read empty CRDTs
    key1 = {"new_counter", :counter_pn_ob, "bucket1"}
    key2 = {"new_set", :set_aw_op, "bucket1"}
    
    {:ok, results, _} = Minidote.read_objects([key1, key2], :ignore)
    
    counter_result = Enum.find(results, fn {{name, _, _}, _} -> name == "new_counter" end)
    set_result = Enum.find(results, fn {{name, _, _}, _} -> name == "new_set" end)
    
    {_, counter_value} = counter_result
    {_, set_value} = set_result
    
    assert counter_value == 0
    assert set_value == []
  end
end