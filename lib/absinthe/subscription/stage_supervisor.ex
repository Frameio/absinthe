defmodule Absinthe.Subscription.StageSupervisor do
  @moduledoc false

  use Supervisor

  def start_link([pubsub, registry, pool_size]) do
    Supervisor.start_link(__MODULE__, {pubsub, registry, pool_size})
  end

  def init({pubsub, _registry, pool_size}) do
    min_demand = 1
    max_demand = pool_size
    shards = Enum.to_list(0..(pool_size - 1))
    buffer_size = 10_000

    unique_producer_name = :"#{Absinthe.Subscription.LocalProducer}.#{:erlang.unique_integer([:monotonic])}"

    children = [
      {Absinthe.Subscription.LocalProducer, [pubsub, shards, buffer_size, unique_producer_name]},
      {Absinthe.Subscription.LocalConsumerSupervisor, [min_demand, max_demand, unique_producer_name]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
