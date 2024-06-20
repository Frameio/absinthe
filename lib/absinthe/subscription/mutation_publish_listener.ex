defmodule Absinthe.Subscription.MutationPublishListener do
  @moduledoc """
  GenStage producer that listens for `publish_mutation` broadcasts
  and buffers events to be processed by MutationPublishProcessor
  """
  use GenStage
  require Logger

  def start_link([_pubsub, _max_queue_length, name] = args) do
    GenStage.start_link(__MODULE__, args, name: name)
  end

  def init([pubsub, max_queue_length, _name]) do
    # publish_mutation callback implementation needs to be updated to use
    # this topic
    :ok = pubsub.subscribe("__absinthe__:subscription:mutation_published")

    {:producer,
     %{
       pubsub: pubsub,
       node: pubsub.node_name(),
       queue: :queue.new(),
       pending_demand: 0,
       max_queue_length: max_queue_length
     }}
  end

  @doc """
  Callback for the consumer to ask for more
  subscriptions to process.
  """
  def handle_demand(demand, state) do
    do_handle_demand(demand, state)
  end

  def handle_info(%{node: payload_node}, %{node: current_node} = state)
      when payload_node == current_node do
    {:noreply, [], state}
  end

  def handle_info(
        %{mutation_result: mutation_result, subscribed_fields: subscribed_fields},
        state
      ) do
    queue = :queue.in({state.pubsub, mutation_result, subscribed_fields}, state.queue)
    queue = drop_oldest_events(queue, state.max_queue_length)
    state = Map.put(state, :queue, queue)

    do_handle_demand(0, state)
  end

  def handle_info(_, state) do
    {:noreply, [], state}
  end

  defp do_handle_demand(demand, state) do
    demand = demand + state.pending_demand
    queue_length = :queue.len(state.queue)

    if queue_length < demand do
      # if we don't have enough items to satisfy demand then
      # send what we have, and save pending demand
      events_to_send = :queue.to_list(state.queue)

      pending_demand = demand - length(events_to_send)

      state =
        state
        |> Map.put(:queue, :queue.new())
        |> Map.put(:pending_demand, pending_demand)

      {:no_reply, events_to_send, state}
    else
      # if we do have enough to satisfy demand, then send what's asked for
      {events_to_send_queue, remaining_events_queue} = :queue.split(demand, state.queue)
      events_to_send = :queue.to_list(events_to_send_queue)

      pending_demand = demand - length(events_to_send)
      pending_demand = if pending_demand < 0, do: 0, else: pending_demand

      state =
        state
        |> Map.put(:queue, remaining_events_queue)
        |> Map.put(:pending_demand, pending_demand)

      {:no_reply, events_to_send, state}
    end
  end

  # drop oldest events until we are under the max_queue_size
  defp drop_oldest_events(queue, max_queue_length) do
    queue_length = :queue.len(queue)

    if queue_length > max_queue_length do
      Logger.warning(
        "[Absinthe.Subscription.MutationPublishListener] Queue length (#{inspect(queue_length)}) exceeds max_queue_length (#{inspect(max_queue_length)}). Dropping oldest events until max_queue_length is reached"
      )

      events_to_drop = :queue.len(queue) - max_queue_length
      {_, new_queue} = :queue.split(events_to_drop, queue)
      new_queue
    else
      queue
    end
  end
end
