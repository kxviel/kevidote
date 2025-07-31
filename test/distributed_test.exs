defmodule DistributedTest do
  use ExUnit.Case

  setup_all do
    TestSetup.init()
    :ok
  end

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
    state_file = "minidote_state_#{node_name}.dets"
    log_file = "minidote_log_#{node_name}.dets"
    File.rm(state_file)
    File.rm(log_file)

    :ok
  end

  test "two node communication without delay" do
    # Start two nodes
    node1 = TestSetup.start_node("node1")
    node2 = TestSetup.start_node("node2")
    
    try do
      # Give nodes time to connect
      Process.sleep(1000)
      
      key = {"distributed_counter", :counter_pn_ob, "test_bucket"}
      
      # Update on node1
      {:ok, clock1} = :rpc.call(node1, Minidote, :update_objects, [[{key, :increment, 10}], :ignore])
      
      # Update on node2  
      {:ok, clock2} = :rpc.call(node2, Minidote, :update_objects, [[{key, :increment, 5}], :ignore])
      
      # Allow time for causal broadcast
      Process.sleep(500)
      
      # Read from both nodes - they should see both updates
      {:ok, results1, _} = :rpc.call(node1, Minidote, :read_objects, [[key], :ignore])
      {:ok, results2, _} = :rpc.call(node2, Minidote, :read_objects, [[key], :ignore])
      
      [{{"distributed_counter", :counter_pn_ob, "test_bucket"}, value1}] = results1
      [{{"distributed_counter", :counter_pn_ob, "test_bucket"}, value2}] = results2
      
      # Both nodes should converge to the same value
      assert value1 == 15
      assert value2 == 15
      
    after
      TestSetup.stop_nodes([node1, node2])
    end
  end

  test "two node communication with artificial delay" do
    # Start two nodes
    node1 = TestSetup.start_node("node1_delay")
    node2 = TestSetup.start_node("node2_delay")
    
    try do
      # Give nodes time to connect
      Process.sleep(1000)
      
      # Add 200ms delay to message passing
      TestSetup.mock_link_layer([node1, node2], %{delay: 200, debug: true})
      
      key = {"delayed_counter", :counter_pn_ob, "test_bucket"}
      
      # Record start time
      start_time = System.monotonic_time(:millisecond)
      
      # Update on node1
      {:ok, _clock1} = :rpc.call(node1, Minidote, :update_objects, [[{key, :increment, 7}], :ignore])
      
      # Immediately read from node2 (should not see update yet due to delay)
      {:ok, results_early, _} = :rpc.call(node2, Minidote, :read_objects, [[key], :ignore])
      [{{"delayed_counter", :counter_pn_ob, "test_bucket"}, early_value}] = results_early
      
      # Should not see the update yet
      assert early_value == 0
      
      # Wait for delay plus some buffer time
      Process.sleep(300)
      
      # Now read from node2 (should see update after delay)
      {:ok, results_late, _} = :rpc.call(node2, Minidote, :read_objects, [[key], :ignore])
      [{{"delayed_counter", :counter_pn_ob, "test_bucket"}, late_value}] = results_late
      
      # Should see the update now
      assert late_value == 7
      
      end_time = System.monotonic_time(:millisecond)
      total_time = end_time - start_time
      
      # Verify that the delay actually occurred (should take at least 200ms)
      assert total_time >= 200
      
    after
      TestSetup.stop_nodes([node1, node2])  
    end
  end

  test "causal ordering with delays" do
    # Start three nodes
    node1 = TestSetup.start_node("causal1")
    node2 = TestSetup.start_node("causal2") 
    node3 = TestSetup.start_node("causal3")
    
    try do
      Process.sleep(1000)
      
      # Add varying delays between nodes
      TestSetup.mock_link_layer([node1, node2, node3], %{
        delay: fn(from, to) ->
          # Different delays based on node pairs
          cond do
            from == node1 and to == node2 -> 100
            from == node2 and to == node3 -> 200
            from == node1 and to == node3 -> 300
            true -> 50
          end
        end,
        debug: true
      })
      
      key = {"causal_counter", :counter_pn_ob, "test_bucket"}
      
      # Sequential operations that should maintain causal order
      {:ok, clock1} = :rpc.call(node1, Minidote, :update_objects, [[{key, :increment, 1}], :ignore])
      Process.sleep(50)
      
      {:ok, clock2} = :rpc.call(node2, Minidote, :update_objects, [[{key, :increment, 2}], clock1])
      Process.sleep(50)
      
      {:ok, _clock3} = :rpc.call(node3, Minidote, :update_objects, [[{key, :increment, 3}], clock2])
      
      # Wait for all updates to propagate
      Process.sleep(1000)
      
      # All nodes should eventually converge to the same value
      {:ok, results1, _} = :rpc.call(node1, Minidote, :read_objects, [[key], :ignore])
      {:ok, results2, _} = :rpc.call(node2, Minidote, :read_objects, [[key], :ignore])
      {:ok, results3, _} = :rpc.call(node3, Minidote, :read_objects, [[key], :ignore])
      
      [{{"causal_counter", :counter_pn_ob, "test_bucket"}, value1}] = results1
      [{{"causal_counter", :counter_pn_ob, "test_bucket"}, value2}] = results2
      [{{"causal_counter", :counter_pn_ob, "test_bucket"}, value3}] = results3
      
      # All should converge to 6 (1 + 2 + 3)
      assert value1 == 6
      assert value2 == 6
      assert value3 == 6
      
    after
      TestSetup.stop_nodes([node1, node2, node3])
    end
  end

  test "network partition simulation" do
    # Start three nodes
    node1 = TestSetup.start_node("partition1")
    node2 = TestSetup.start_node("partition2")
    node3 = TestSetup.start_node("partition3")
    
    try do
      Process.sleep(1000)
      
      # Simulate network partition: very high delay between some nodes
      TestSetup.mock_link_layer([node1, node2, node3], %{
        delay: fn(from, to) ->
          # Partition: node1-node2 connected, but both isolated from node3
          if (from == node3 or to == node3) do
            5000  # 5 second delay simulates partition
          else
            50    # Normal delay within partition
          end
        end,
        debug: true
      })
      
      key = {"partition_test", :set_aw_op, "test_bucket"}
      
      # Operations within the connected partition (node1, node2)
      {:ok, _} = :rpc.call(node1, Minidote, :update_objects, [[{key, :add, "item_from_node1"}], :ignore])
      {:ok, _} = :rpc.call(node2, Minidote, :update_objects, [[{key, :add, "item_from_node2"}], :ignore])
      
      # Operation on isolated node
      {:ok, _} = :rpc.call(node3, Minidote, :update_objects, [[{key, :add, "item_from_node3"}], :ignore])
      
      # Allow propagation within partition
      Process.sleep(200)
      
      # Check that node1 and node2 see each other's updates
      {:ok, results1, _} = :rpc.call(node1, Minidote, :read_objects, [[key], :ignore])
      {:ok, results2, _} = :rpc.call(node2, Minidote, :read_objects, [[key], :ignore])
      
      [{{"partition_test", :set_aw_op, "test_bucket"}, value1}] = results1  
      [{{"partition_test", :set_aw_op, "test_bucket"}, value2}] = results2
      
      # Node1 and node2 should see each other's items but not node3's
      assert "item_from_node1" in value1
      assert "item_from_node2" in value1
      assert "item_from_node3" not in value1
      
      assert "item_from_node1" in value2
      assert "item_from_node2" in value2
      assert "item_from_node3" not in value2
      
      # Node3 should only see its own item
      {:ok, results3, _} = :rpc.call(node3, Minidote, :read_objects, [[key], :ignore])
      [{{"partition_test", :set_aw_op, "test_bucket"}, value3}] = results3
      
      assert "item_from_node1" not in value3
      assert "item_from_node2" not in value3  
      assert "item_from_node3" in value3
      
    after
      TestSetup.stop_nodes([node1, node2, node3])
    end
  end
end