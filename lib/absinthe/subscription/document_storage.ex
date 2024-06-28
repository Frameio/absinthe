defmodule Absinthe.Subscription.DocumentStorage do
  @moduledoc """
  Behaviour for storing subscription documents. Used to tell
  Absinthe how to store documents and the field keys associated with those
  documents.

  By default, Absinthe uses `Absinthe.Subscription.DefaultDocumentStorage` as
  the storage for subscription documents. This behaviour can be implemented to
  allow for a custom storage solution if needed.

  When starting `Absinthe.Subscription`, include `storage`. Defaults to `Absinthe.Subscription.DefaultDocumentStorage`

  ```elixir
  {Absinthe.Subscription, pubsub: MyApp.Pubsub, storage: MyApp.DocumentStorage}
  ```
  """

  alias Absinthe.Subscription
  alias Absinthe.Subscription.PipelineSerializer

  @doc """
  Adds `doc` to storage with `doc_id` as the key. Associates the given
  `field_keys` with `doc_id`.
  """
  @callback put(
              pubsub :: atom,
              doc_id :: term,
              doc :: %{
                initial_phases: Absinthe.Subscription.PipelineSerializer.packed_pipeline(),
                source: binary()
              },
              field_keys :: [{field :: term, key :: term}]
            ) ::
              {:ok, term} | {:error, :reason}

  @doc """
  Removes the document. Along with any field_keys associated with it
  """
  @callback delete(pubsub :: atom, doc_id :: term) :: :ok

  @doc """
  Get all docs associated with `field_key`
  """
  @callback get_docs_by_field_key(
              pubsub :: atom,
              field_key :: {field :: term, key :: term}
            ) ::
              map()

  @doc false
  def put(pubsub, doc_id, doc, field_keys) do
    storage_module = Subscription.storage_module(pubsub)

    :telemetry.span(
      [:absinthe, :subscription, :storage, :put],
      %{
        doc_id: doc_id,
        doc: doc,
        field_keys: field_keys,
        storage_module: storage_module
      },
      fn ->
        field_keys = List.wrap(field_keys)

        doc_value = %{
          initial_phases: PipelineSerializer.pack(doc.initial_phases),
          source: doc.source
        }

        result = storage_module.put(pubsub, doc_id, doc_value, field_keys)

        {result,
         %{
           doc_id: doc_id,
           doc: doc,
           field_keys: field_keys,
           storage_module: storage_module
         }}
      end
    )
  end

  @doc false
  def delete(pubsub, doc_id) do
    storage_module = Subscription.storage_module(pubsub)

    :telemetry.span(
      [:absinthe, :subscription, :storage, :delete],
      %{
        doc_id: doc_id,
        storage_module: storage_module
      },
      fn ->
        result = storage_module.delete(pubsub, doc_id)

        {result,
         %{
           doc_id: doc_id,
           storage_module: storage_module
         }}
      end
    )
  end

  @doc false
  def get_docs_by_field_key(pubsub, field_key) do
    storage_module = Subscription.storage_module(pubsub)

    :telemetry.span(
      [:absinthe, :subscription, :storage, :get_docs_by_field_key],
      %{
        field_key: field_key,
        storage_module: storage_module
      },
      fn ->
        result =
          pubsub
          |> storage_module.get_docs_by_field_key(field_key)
          |> Enum.map(fn {doc_id, %{initial_phases: initial_phases} = doc} ->
            initial_phases = PipelineSerializer.unpack(initial_phases)
            {doc_id, Map.put(doc, :initial_phases, initial_phases)}
          end)
          |> Map.new()

        {result,
         %{
           field_key: field_key,
           storage_module: storage_module
         }}
      end
    )
  end
end
