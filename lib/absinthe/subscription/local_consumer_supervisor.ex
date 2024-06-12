defmodule Absinthe.Subscription.LocalConsumerSupervisor do
  @moduledoc """
  Supervisor for consuming publish_mutation requests
  """

  use ConsumerSupervisor

  alias Absinthe.Subscription.LocalProducer
  alias Absinthe.Subscription.LocalConsumer

  def start_link(args) do
    ConsumerSupervisor.start_link(__MODULE__, args)
  end

  def init([min_demand, max_demand]) do
    children = [%{id: LocalConsumer, start: {LocalConsumer, :start_link, []}, restart: :transient}]
    opts = [strategy: :one_for_one, subscribe_to: [{LocalProducer, min_demand: min_demand, max_demand: max_demand}]]
    ConsumerSupervisor.init(children, opts)
  end
end
