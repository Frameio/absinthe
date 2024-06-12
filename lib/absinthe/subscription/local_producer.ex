defmodule Absinthe.Subscription.LocalProducer do
  @moduledoc """
  GenStage producer that listens for `publish_mutation` broadcasts
  in order to process the subscriptions on this node.
  """
  use GenStage

  def start_link(args) do
    GenStage.start_link(__MODULE__, args)
  end

  def topic(shard), do: "__absinthe__:proxy:#{shard}"

  def init([pubsub, shards, buffer_size]) do
    Enum.each(shards, fn shard ->
      :ok = pubsub.subscribe(topic(shard))
    end)

    # default buffer_size
    {:producer, %{pubsub: pubsub, node: pubsub.node_name()}, buffer_size: buffer_size}
  end

  @doc """
  Callback for the consumer to ask for more
  subscriptions to process. Since we will be sending
  them immediately when we get a message from pubsub,
  this just sends an empty list
  """
  def handle_demand(_demand, state) do
    {:noreply, [], state}
  end

  def handle_info(payload, state) do
    if payload.node == state.node do
      {:noreply, [], state}
    else
      {:noreply, [{state.pubsub, payload.mutation_result, payload.subscribed_fields}], state}
    end
  end
end
