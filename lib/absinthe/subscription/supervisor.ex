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

    pool_size = Keyword.get(opts, :pool_size, System.schedulers_online() * 2)
    compress_registry? = Keyword.get(opts, :compress_registry?, true)

    storage_implementation =
      Keyword.get(opts, :storage_implementation, Absinthe.Subscription.DefaultDocumentStorage)

    Supervisor.start_link(
      __MODULE__,
      {pubsub, pool_size, compress_registry?, storage_implementation}
    )
  end

  def init({pubsub, pool_size, compress_registry?, storage_implementation}) do
    registry_name = Absinthe.Subscription.registry_name(pubsub)
    storage_name = Absinthe.Subscription.storage_name(pubsub)
    meta = [pool_size: pool_size, storage_implementation: storage_implementation]

    children = [
      {Registry,
       [
         keys: :unique,
         name: registry_name,
         meta: meta
       ]},
      storage_implementation.child_spec(
        keys: :duplicate,
        name: storage_name,
        partitions: System.schedulers_online(),
        compressed: compress_registry?
      ),
      {Absinthe.Subscription.ProxySupervisor, [pubsub, registry_name, pool_size]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
