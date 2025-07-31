defmodule PersistenceManager do
  use GenServer
  require Logger

  @moduledoc """
  Handles crash recovery and log pruning for Minidote.
  
  This module manages persistent storage of CRDT states and operation logs
  to enable crash recovery. It periodically snapshots the current state
  and prunes old log entries to prevent unbounded growth.
  """

  @table_name :minidote_state
  @log_table_name :minidote_log
  @snapshot_interval 10_000  # 10 seconds
  @log_retention_size 1000   # Keep last 1000 operations

  defstruct [:state_table, :log_table, :timer_ref]

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def persist_state(crdt_states) do
    GenServer.cast(__MODULE__, {:persist_state, crdt_states})
  end

  def log_operation(operation) do
    GenServer.cast(__MODULE__, {:log_operation, operation})
  end

  def restore_state() do
    GenServer.call(__MODULE__, :restore_state)
  end

  @impl true
  def init(_) do
    node_name = Atom.to_string(node())
    state_file = "minidote_state_#{node_name}.dets"
    log_file = "minidote_log_#{node_name}.dets"
    
    {:ok, state_table} = :dets.open_file(@table_name, [file: String.to_charlist(state_file)])
    {:ok, log_table} = :dets.open_file(@log_table_name, [file: String.to_charlist(log_file)])
    
    timer_ref = Process.send_after(self(), :snapshot, @snapshot_interval)
    
    state = %__MODULE__{
      state_table: state_table,
      log_table: log_table,
      timer_ref: timer_ref
    }
    
    Logger.info("PersistenceManager started with files: #{state_file}, #{log_file}")
    {:ok, state}
  end

  @impl true
  def handle_cast({:persist_state, crdt_states}, state) do
    :dets.insert(state.state_table, {:current_state, crdt_states})
    :dets.sync(state.state_table)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:log_operation, operation}, state) do
    timestamp = :os.system_time(:microsecond)
    :dets.insert(state.log_table, {timestamp, operation})
    {:noreply, state}
  end

  @impl true
  def handle_call(:restore_state, _from, state) do
    case :dets.lookup(state.state_table, :current_state) do
      [{:current_state, crdt_states}] ->
        {:reply, {:ok, crdt_states}, state}
      [] ->
        {:reply, {:ok, %{}}, state}
    end
  end

  @impl true
  def handle_info(:snapshot, state) do
    try do
      prune_old_logs(state.log_table)
      Logger.debug("Snapshot and log pruning completed")
    rescue
      error ->
        Logger.error("Error during snapshot/pruning: #{inspect error}")
    end
    
    timer_ref = Process.send_after(self(), :snapshot, @snapshot_interval)
    new_state = %{state | timer_ref: timer_ref}
    {:noreply, new_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Unhandled info message in PersistenceManager: #{inspect msg}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end
    
    :dets.close(state.state_table)
    :dets.close(state.log_table)
    :ok
  end

  defp prune_old_logs(log_table) do
    all_logs = :dets.select(log_table, [{{:'$1', :'$2'}, [], [:'$_']}])
    
    if length(all_logs) > @log_retention_size do
      sorted_logs = Enum.sort_by(all_logs, fn {timestamp, _op} -> timestamp end, :desc)
      {keep_logs, remove_logs} = Enum.split(sorted_logs, @log_retention_size)
      
      Enum.each(remove_logs, fn {timestamp, _op} ->
        :dets.delete(log_table, timestamp)
      end)
      
      :dets.sync(log_table)
      Logger.info("Pruned #{length(remove_logs)} old log entries, kept #{length(keep_logs)}")
    end
  end
end