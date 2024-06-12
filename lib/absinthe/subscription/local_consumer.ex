defmodule Absinthe.Subscription.LocalConsumer do
  @moduledoc """
  Processes the publish_mutation request on the
  local node.
  """

  def start_link({pubsub, mutation_result, subscribed_fields}) do
    Task.start_link(fn ->
      Absinthe.Subscription.Local.publish_mutation(pubsub, mutation_result, subscribed_fields)
    end)
  end
end
