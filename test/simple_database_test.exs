defmodule SimpleDatabaseTest do
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

    # Start the application components
    {:ok, _} = PersistenceManager.start_link()
    {:ok, _} = Minidote.Server.start_link(Minidote.Server)
    
    Process.sleep(50)
    :ok
  end

  test "can store and retrieve a number" do
    key = {"my_number", :counter_pn_ob, "my_bucket"}
    
    # Store the number 42
    {:ok, _clock} = Minidote.update_objects([{key, :increment, 42}], :ignore)
    
    # Get it back
    {:ok, results, _clock} = Minidote.read_objects([key], :ignore)
    [{_, value}] = results
    
    assert value == 42
  end

  test "can store items in a list" do
    key = {"shopping_list", :set_aw_op, "groceries"}
    
    # Add items to shopping list
    {:ok, clock1} = Minidote.update_objects([{key, :add, "milk"}], :ignore)
    {:ok, _clock2} = Minidote.update_objects([{key, :add, "bread"}], clock1)
    
    # Check our list
    {:ok, results, _clock} = Minidote.read_objects([key], :ignore)
    [{_, items}] = results
    
    assert "milk" in items
    assert "bread" in items
  end

  test "can update a value" do
    key = {"user_name", :lww_register, "profile"}
    
    # Set initial name
    {:ok, clock1} = Minidote.update_objects([{key, :assign, "Alice"}], :ignore)
    
    # Update name
    {:ok, _clock2} = Minidote.update_objects([{key, :assign, "Bob"}], clock1)
    
    # Check current name
    {:ok, results, _clock} = Minidote.read_objects([key], :ignore)
    [{_, name}] = results
    
    assert name == "Bob"
  end
end