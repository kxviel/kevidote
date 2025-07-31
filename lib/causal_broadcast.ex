defmodule CausalBroadcast do
  use GenServer
  require Logger

  @moduledoc """
  Causal broadcast implementation using vector clocks.
  Ensures causal ordering of messages across distributed nodes.
  """

  @type vector_clock :: %{atom() => integer()}
  @type message :: {term(), vector_clock()}

  defstruct [:link_layer, :node_id, :vector_clock, :pending_messages, :delivery_handler]

  def start_link(group_name, delivery_handler) do
    GenServer.start_link(__MODULE__, {group_name, delivery_handler}, name: __MODULE__)
  end

  def broadcast(message) do
    GenServer.cast(__MODULE__, {:broadcast, message})
  end

  def get_vector_clock() do
    GenServer.call(__MODULE__, :get_vector_clock)
  end

  @impl true
  def init({group_name, delivery_handler}) do
    {:ok, link_layer} = LinkLayerDistr.start_link(group_name)
    LinkLayer.register(link_layer, self())
    node_id = node()
    
    state = %__MODULE__{
      link_layer: link_layer,
      node_id: node_id,
      vector_clock: %{node_id => 0},
      pending_messages: [],
      delivery_handler: delivery_handler
    }
    
    Logger.info("CausalBroadcast started on node #{node_id}")
    {:ok, state}
  end

  @impl true
  def handle_cast({:broadcast, message}, state) do
    new_clock = Map.update(state.vector_clock, state.node_id, 1, &(&1 + 1))
    
    broadcast_message = {message, new_clock}
    {:ok, other_nodes} = LinkLayer.other_nodes(state.link_layer)
    
    Enum.each(other_nodes, fn node ->
      LinkLayer.send(state.link_layer, broadcast_message, node)
    end)
    
    # Don't apply locally - the originating node has already applied the update
    
    new_state = %{state | vector_clock: new_clock}
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_vector_clock, _from, state) do
    {:reply, state.vector_clock, state}
  end

  @impl true
  def handle_info({:message, {message, sender_clock}}, state) do
    sender_node = extract_sender_node(sender_clock, state.vector_clock)
    
    case can_deliver?(sender_clock, state.vector_clock, sender_node) do
      true ->
        apply(state.delivery_handler, :handle_causal_message, [message, sender_clock])
        
        new_clock = merge_vector_clocks(state.vector_clock, sender_clock)
        new_state = %{state | vector_clock: new_clock}
        
        deliver_pending_messages(new_state)
        
      false ->
        new_pending = [{message, sender_clock} | state.pending_messages]
        new_state = %{state | pending_messages: new_pending}
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Unhandled info message in CausalBroadcast: #{inspect msg}")
    {:noreply, state}
  end

  defp can_deliver?(sender_clock, local_clock, sender_node) do
    sender_clock
    |> Enum.all?(fn {node, timestamp} ->
      cond do
        node == sender_node ->
          Map.get(local_clock, node, 0) == timestamp - 1
        true ->
          Map.get(local_clock, node, 0) >= timestamp
      end
    end)
  end

  defp extract_sender_node(sender_clock, local_clock) do
    sender_clock
    |> Enum.find(fn {node, timestamp} ->
      Map.get(local_clock, node, 0) < timestamp
    end)
    |> case do
      {node, _} -> node
      nil -> node()
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

  defp deliver_pending_messages(state) do
    {deliverable, still_pending} = 
      Enum.split_with(state.pending_messages, fn {_message, sender_clock} ->
        sender_node = extract_sender_node(sender_clock, state.vector_clock)
        can_deliver?(sender_clock, state.vector_clock, sender_node)
      end)
    
    final_clock = Enum.reduce(deliverable, state.vector_clock, fn {message, sender_clock}, acc_clock ->
      apply(state.delivery_handler, :handle_causal_message, [message, sender_clock])
      merge_vector_clocks(acc_clock, sender_clock)
    end)
    
    new_state = %{state | vector_clock: final_clock, pending_messages: still_pending}
    
    if length(deliverable) > 0 do
      deliver_pending_messages(new_state)
    else
      {:noreply, new_state}
    end
  end
end