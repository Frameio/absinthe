defmodule Absinthe.Subscription.Supervisor do
  @moduledoc false

  use Supervisor

  @spec start_link(atom() | [Absinthe.Subscription.opt()]) :: Supervisor.on_start()
  def start_link(pubsub) when is_atom(pubsub) do
    # start_link/1 used to take a single argument - the pub-sub - so in order
    # to maintain compatibility for existing users of the library we still
    # accept this argument and transform it into a keyword list.
    start_link(pubsub: pubsub)
  end

  def start_link(opts) when is_list(opts) do
    pubsub =
      case Keyword.fetch!(opts, :pubsub) do
        [module] when is_atom(module) ->
          module

        module ->
          module
      end

    max_demand = Keyword.get(opts, :max_demand, System.schedulers_online() * 2)
    max_queue_length = Keyword.get(opts, :max_queue_length, 10_000)
    compress_registry? = Keyword.get(opts, :compress_registry?, true)

    Supervisor.start_link(__MODULE__, {pubsub, max_demand, max_queue_length, compress_registry?})
  end

  def init({pubsub, max_demand, max_queue_length, compress_registry?}) do
    registry_name = Absinthe.Subscription.registry_name(pubsub)

    children = [
      {Registry,
       [
         keys: :duplicate,
         name: registry_name,
         partitions: System.schedulers_online(),
         meta: [],
         compressed: compress_registry?
       ]},
      {Absinthe.Subscription.MutationPublishSupervisor, [pubsub, max_demand, max_queue_length]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
