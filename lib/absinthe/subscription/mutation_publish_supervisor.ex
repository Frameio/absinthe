defmodule Absinthe.Subscription.MutationPublishSupervisor do
  @moduledoc false

  use Supervisor

  def start_link([pubsub, max_demand, max_queue_length]) do
    Supervisor.start_link(__MODULE__, {pubsub, max_demand, max_queue_length})
  end

  def init({pubsub, max_demand, max_queue_length}) do
    unique_producer_name =
      :"#{Absinthe.Subscription.LocalProducer}.#{:erlang.unique_integer([:monotonic])}"

    children = [
      {Absinthe.Subscription.MutationPublishListener,
       [pubsub, max_queue_length, unique_producer_name]},
      {Absinthe.Subscription.LocalConsumerSupervisor, [max_demand, unique_producer_name]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
