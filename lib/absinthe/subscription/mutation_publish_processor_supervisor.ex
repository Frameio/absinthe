defmodule Absinthe.Subscription.MutationPublishProcessorSupervisor do
  @moduledoc """
  Supervisor for consuming publish_mutation requests
  """

  use ConsumerSupervisor

  alias Absinthe.Subscription.MutationPublishProcessor

  def start_link(args) do
    ConsumerSupervisor.start_link(__MODULE__, args)
  end

  def init([max_demand, producer_name]) do
    children = [
      %{
        id: MutationPublishProcessor,
        start: {MutationPublishProcessor, :start_link, []},
        restart: :transient
      }
    ]

    opts = [
      strategy: :one_for_one,
      subscribe_to: [{producer_name, max_demand: max_demand}]
    ]

    ConsumerSupervisor.init(children, opts)
  end
end
