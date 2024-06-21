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

    document_storage =
      Keyword.get(opts, :document_storage, Absinthe.Subscription.DefaultDocumentStorage)

    storage_opts =
      case document_storage do
        Absinthe.Subscription.DefaultDocumentStorage ->
          [
            keys: :duplicate,
            partitions: System.schedulers_online(),
            compressed: compress_registry?
          ]

        _ ->
          Keyword.get(opts, :storage_opts, Keyword.new())
      end

    Supervisor.start_link(
      __MODULE__,
      {pubsub, pool_size, document_storage, storage_opts}
    )
  end

  def init({pubsub, pool_size, document_storage, storage_opts}) do
    registry_name = Absinthe.Subscription.registry_name(pubsub)
    meta = [pool_size: pool_size, document_storage: document_storage]

    storage_opts =
      Keyword.put(storage_opts, :name, Absinthe.Subscription.document_storage_name(pubsub))

    children = [
      {Registry,
       [
         keys: :unique,
         name: registry_name,
         meta: meta
       ]},
      document_storage.child_spec(storage_opts),
      {Absinthe.Subscription.ProxySupervisor, [pubsub, registry_name, pool_size]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
