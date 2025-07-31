defmodule Minidote.Server do
  use GenServer
  require Logger

  @moduledoc """
  The MinidoteServer GenServer that manages CRDT state and handles causally consistent operations.
  """

  @type key :: {binary(), CRDT.t(), binary()}
  @type vector_clock :: %{atom() => integer()}
  @type crdt_state :: %{key() => term()}
  @type waiting_request :: {GenServer.from(), term()}

  defstruct [
    :link_layer, 
    :vector_clock, 
    :crdt_states, 
    :waiting_requests,
    :causal_broadcast
  ]

  def start_link(server_name) do
    GenServer.start_link(__MODULE__, [], name: server_name)
  end

  def read_objects(objects, clock) do
    GenServer.call(Minidote.Server, {:read_objects, objects, clock})
  end

  def update_objects(updates, clock) do
    GenServer.call(Minidote.Server, {:update_objects, updates, clock})
  end

  @impl true
  def init(_) do
    {:ok, causal_broadcast} = CausalBroadcast.start_link(:minidote, __MODULE__)
    
    {:ok, restored_states} = PersistenceManager.restore_state()
    
    state = %__MODULE__{
      vector_clock: %{node() => 0},
      crdt_states: restored_states,
      waiting_requests: [],
      causal_broadcast: causal_broadcast
    }
    
    Logger.info("MinidoteServer started on node #{node()}, restored #{map_size(restored_states)} CRDT states")
    {:ok, state}
  end

  @impl true
  def handle_call({:read_objects, objects, clock}, from, state) do
    case clock do
      :ignore ->
        results = Enum.map(objects, fn key -> 
          get_crdt_value(key, state.crdt_states) 
        end)
        {:reply, {:ok, results, state.vector_clock}, state}
        
      client_clock when is_map(client_clock) ->
        case clock_satisfies?(client_clock, state.vector_clock) do
          true ->
            results = Enum.map(objects, fn key -> 
              get_crdt_value(key, state.crdt_states) 
            end)
            {:reply, {:ok, results, state.vector_clock}, state}
            
          false ->
            new_waiting = [{from, {:read_objects, objects, clock}} | state.waiting_requests]
            new_state = %{state | waiting_requests: new_waiting}
            {:noreply, new_state}
        end
    end
  end

  @impl true  
  def handle_call({:update_objects, updates, clock}, from, state) do
    case clock do
      :ignore ->
        process_updates(updates, from, state)
        
      client_clock when is_map(client_clock) ->
        case clock_satisfies?(client_clock, state.vector_clock) do
          true ->
            process_updates(updates, from, state)
            
          false ->
            new_waiting = [{from, {:update_objects, updates, clock}} | state.waiting_requests]
            new_state = %{state | waiting_requests: new_waiting}
            {:noreply, new_state}
        end
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Unhandled info message in MinidoteServer: #{inspect msg}")
    {:noreply, state}
  end

  def handle_causal_message(downstream_effects, sender_clock) do
    GenServer.cast(Minidote.Server, {:apply_downstream_effects, downstream_effects, sender_clock})
  end

  @impl true
  def handle_cast({:apply_downstream_effects, downstream_effects, sender_clock}, state) do
    new_crdt_states = Enum.reduce(downstream_effects, state.crdt_states, fn {key, type, effect}, acc ->
      current_state = Map.get(acc, key, CRDT.new(type))
      {:ok, updated_state} = CRDT.update(type, effect, current_state)
      Map.put(acc, key, updated_state)
    end)
    
    new_vector_clock = merge_vector_clocks(state.vector_clock, sender_clock)
    
    PersistenceManager.log_operation({:remote_update, downstream_effects, sender_clock})
    PersistenceManager.persist_state(new_crdt_states)
    
    new_state = %{state | 
      crdt_states: new_crdt_states, 
      vector_clock: new_vector_clock
    }
    
    process_waiting_requests(new_state)
  end

  defp process_updates(updates, from, state) do
    downstream_effects = Enum.map(updates, fn {key, operation, args} ->
      {_key_id, type, _bucket} = key
      current_state = Map.get(state.crdt_states, key, CRDT.new(type))
      
      {:ok, effect} = CRDT.downstream(type, {operation, args}, current_state)
      {key, type, effect}
    end)
    
    new_crdt_states = Enum.reduce(downstream_effects, state.crdt_states, fn {key, type, effect}, acc ->
      current_state = Map.get(acc, key, CRDT.new(type))
      {:ok, updated_state} = CRDT.update(type, effect, current_state)
      Map.put(acc, key, updated_state)
    end)
    
    new_vector_clock = Map.update(state.vector_clock, node(), 1, &(&1 + 1))
    
    CausalBroadcast.broadcast(downstream_effects)
    
    PersistenceManager.log_operation({:update, updates, new_vector_clock})
    PersistenceManager.persist_state(new_crdt_states)
    
    new_state = %{state | 
      crdt_states: new_crdt_states, 
      vector_clock: new_vector_clock
    }
    
    GenServer.reply(from, {:ok, new_vector_clock})
    {:noreply, new_state}
  end

  defp get_crdt_value(key, crdt_states) do
    {key_id, type, bucket} = key
    
    case Map.get(crdt_states, key) do
      nil -> 
        initial_state = CRDT.new(type)
        value = CRDT.value(type, initial_state)
        {{key_id, type, bucket}, value}
      state -> 
        value = CRDT.value(type, state)
        {{key_id, type, bucket}, value}
    end
  end

  defp clock_satisfies?(client_clock, server_clock) do
    Enum.all?(client_clock, fn {node, timestamp} ->
      Map.get(server_clock, node, 0) >= timestamp
    end)
  end

  defp merge_vector_clocks(local_clock, remote_clock) do
    all_nodes = MapSet.union(MapSet.new(Map.keys(local_clock)), MapSet.new(Map.keys(remote_clock)))
    
    Enum.reduce(all_nodes, %{}, fn node, acc ->
      local_val = Map.get(local_clock, node, 0)
      remote_val = Map.get(remote_clock, node, 0)
      Map.put(acc, node, max(local_val, remote_val))
    end)
  end

  defp process_waiting_requests(state) do
    {processable, still_waiting} = Enum.split_with(state.waiting_requests, fn {_from, request} ->
      case request do
        {:read_objects, _objects, client_clock} ->
          clock_satisfies?(client_clock, state.vector_clock)
        {:update_objects, _updates, client_clock} ->
          clock_satisfies?(client_clock, state.vector_clock)
      end
    end)
    
    new_state = Enum.reduce(processable, state, fn {from, request}, acc_state ->
      case request do
        {:read_objects, objects, _clock} ->
          results = Enum.map(objects, fn key -> 
            get_crdt_value(key, acc_state.crdt_states) 
          end)
          GenServer.reply(from, {:ok, results, acc_state.vector_clock})
          acc_state
          
        {:update_objects, updates, _clock} ->
          {_reply, new_acc_state} = process_updates(updates, from, acc_state)
          new_acc_state
      end
    end)
    
    final_state = %{new_state | waiting_requests: still_waiting}
    {:noreply, final_state}
  end
end