defmodule PersistenceManager do
  use GenServer
  require Logger

  @moduledoc """
  Simple persistence for crash recovery.
  """

  defstruct [
    :log_table,
    :snapshot_table,
    :next_log_id,
    :last_snapshot_id
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def log_operation(operation) do
    GenServer.cast(__MODULE__, {:log_operation, operation})
  end

  def snapshot_state(crdt_states, vector_clock) do
    GenServer.cast(__MODULE__, {:snapshot_state, crdt_states, vector_clock})
  end

  def restore_state() do
    GenServer.call(__MODULE__, :restore_state)
  end

  def prune_log() do
    GenServer.cast(__MODULE__, :prune_log)
  end

  @impl true
  def init(_opts) do
    node_name = Atom.to_string(node())
    log_file = "minidote_log_#{node_name}.dets"
    snapshot_file = "minidote_snapshot_#{node_name}.dets"
    
    {:ok, log_table} = :dets.open_file(:log_table, [{:file, String.to_charlist(log_file)}])
    {:ok, snapshot_table} = :dets.open_file(:snapshot_table, [{:file, String.to_charlist(snapshot_file)}])
    
    next_log_id = case :dets.select(log_table, [{{:'$1', :_}, [], [:'$1']}]) do
      [] -> 1
      ids -> Enum.max(ids) + 1
    end
    
    last_snapshot_id = case :dets.lookup(snapshot_table, :last_snapshot_id) do
      [{:last_snapshot_id, id}] -> id
      [] -> 0
    end
    
    state = %__MODULE__{
      log_table: log_table,
      snapshot_table: snapshot_table,
      next_log_id: next_log_id,
      last_snapshot_id: last_snapshot_id
    }
    
    Logger.info("PersistenceManager started for node #{node_name}, next_log_id: #{next_log_id}, last_snapshot_id: #{last_snapshot_id}")
    {:ok, state}
  end

  @impl true
  def handle_cast({:log_operation, operation}, state) do
    timestamp = :os.system_time(:millisecond)
    log_entry = {state.next_log_id, timestamp, operation}
    
    :ok = :dets.insert(state.log_table, {state.next_log_id, log_entry})
    :dets.sync(state.log_table)
    
    new_state = %{state | next_log_id: state.next_log_id + 1}
    
    # Check if we need to prune
    if should_prune?(new_state) do
      GenServer.cast(self(), :prune_log)
    end
    
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:snapshot_state, crdt_states, vector_clock}, state) do
    snapshot_id = state.next_log_id - 1
    timestamp = :os.system_time(:millisecond)
    
    snapshot_data = %{
      crdt_states: crdt_states,
      vector_clock: vector_clock,
      timestamp: timestamp,
      snapshot_id: snapshot_id
    }
    
    :ok = :dets.insert(state.snapshot_table, {:current_snapshot, snapshot_data})
    :ok = :dets.insert(state.snapshot_table, {:last_snapshot_id, snapshot_id})
    :dets.sync(state.snapshot_table)
    
    new_state = %{state | last_snapshot_id: snapshot_id}
    
    Logger.info("Created snapshot #{snapshot_id} with #{map_size(crdt_states)} CRDT states")
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:prune_log, state) do
    if state.last_snapshot_id > 0 do
      # Remove all log entries up to and including the last snapshot
      entries_to_remove = :dets.select(state.log_table, [
        {{:'$1', :_}, [{:'=<', :'$1', state.last_snapshot_id}], [:'$1']}
      ])
      
      Enum.each(entries_to_remove, fn log_id ->
        :dets.delete(state.log_table, log_id)
      end)
      
      :dets.sync(state.log_table)
      
      Logger.info("Pruned #{length(entries_to_remove)} log entries up to snapshot #{state.last_snapshot_id}")
    end
    
    {:noreply, state}
  end

  @impl true
  def handle_call(:restore_state, _from, state) do
    # First try to restore from snapshot
    {crdt_states, vector_clock, replay_from_id} = case :dets.lookup(state.snapshot_table, :current_snapshot) do
      [{:current_snapshot, snapshot_data}] ->
        %{
          crdt_states: crdt_states,
          vector_clock: vector_clock,
          snapshot_id: snapshot_id
        } = snapshot_data
        
        Logger.info("Restored from snapshot #{snapshot_id} with #{map_size(crdt_states)} CRDT states")
        {crdt_states, vector_clock, snapshot_id + 1}
        
      [] ->
        Logger.info("No snapshot found, starting from empty state")
        {%{}, %{node() => 0}, 1}
    end
    
    # Replay operations from log since snapshot
    log_entries = :dets.select(state.log_table, [
      {{:'$1', :'$2'}, [{:'>=', :'$1', replay_from_id}], [:'$2']}
    ])
    
    sorted_entries = Enum.sort_by(log_entries, fn {log_id, _timestamp, _operation} -> log_id end)
    
    {final_crdt_states, final_vector_clock} = Enum.reduce(sorted_entries, {crdt_states, vector_clock}, 
      fn {_log_id, _timestamp, operation}, {acc_states, acc_clock} ->
        apply_logged_operation(operation, acc_states, acc_clock)
      end)
    
    Logger.info("Replayed #{length(sorted_entries)} operations from log")
    
    {:reply, {:ok, final_crdt_states, final_vector_clock}, state}
  end

  @impl true
  def terminate(_reason, state) do
    :dets.close(state.log_table)
    :dets.close(state.snapshot_table)
    :ok
  end

  defp should_prune?(state) do
    entries_after_snapshot = length(:dets.select(state.log_table, [
      {{:'$1', :_}, [{:'>', :'$1', state.last_snapshot_id}], [true]}
    ]))
    
    entries_after_snapshot > 1000
  end

  defp apply_logged_operation(operation, crdt_states, vector_clock) do
    case operation do
      {:update, updates, operation_clock} ->
        # Apply updates to CRDT states
        new_crdt_states = Enum.reduce(updates, crdt_states, fn {key, operation, args}, acc ->
          {_key_id, type, _bucket} = key
          current_state = Map.get(acc, key, CRDT.new(type))
          
          {:ok, effect} = CRDT.downstream(type, {operation, args}, current_state)
          {:ok, updated_state} = CRDT.update(type, effect, current_state)
          Map.put(acc, key, updated_state)
        end)
        
        # Merge vector clocks
        new_vector_clock = merge_vector_clocks(vector_clock, operation_clock)
        {new_crdt_states, new_vector_clock}
        
      {:remote_update, downstream_effects, sender_clock} ->
        # Apply remote updates
        new_crdt_states = Enum.reduce(downstream_effects, crdt_states, fn {key, type, effect}, acc ->
          current_state = Map.get(acc, key, CRDT.new(type))
          {:ok, updated_state} = CRDT.update(type, effect, current_state)
          Map.put(acc, key, updated_state)
        end)
        
        new_vector_clock = merge_vector_clocks(vector_clock, sender_clock)
        {new_crdt_states, new_vector_clock}
        
      _ ->
        # Unknown operation, skip
        {crdt_states, vector_clock}
    end
  end

  defp merge_vector_clocks(local_clock, remote_clock) do
    all_nodes = MapSet.union(MapSet.new(Map.keys(local_clock)), MapSet.new(Map.keys(remote_clock)))
    
    Enum.reduce(all_nodes, %{}, fn node, acc ->
      local_val = Map.get(local_clock, node, 0)
      remote_val = Map.get(remote_clock, node, 0)
      Map.put(acc, node, max(local_val, remote_val))
    end)
  end
end