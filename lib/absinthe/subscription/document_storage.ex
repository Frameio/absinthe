defmodule Absinthe.Subscription.DocumentStorage do
  @moduledoc """
  Behaviour for storing subscription documents. Used to tell
  Absinthe how to store documents and the field keys associated with those
  documents.
  """

  alias Absinthe.Subscription
  alias Absinthe.Subscription.PipelineSerializer

  @doc """
  Child spec to determine how to start the
  Document storage process. This will be supervised. Absinthe will give
  the process a name and that name will be passed in the other callbacks
  in order to reference it there.
  """
  @callback child_spec(opts :: Keyword.t()) :: Supervisor.child_spec()

  @doc """
  Adds `doc` to storage with `doc_id` as the key. Associates the given
  `field_keys` with `doc_id`.
  """
  @callback put(
              storage_process_name :: atom,
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
  @callback delete(storage_process_name :: atom, doc_id :: term) :: :ok

  @doc """
  Get all docs associated with `field_key`
  """
  @callback get_docs_by_field_key(
              storage_process_name :: atom,
              field_key :: {field :: term, key :: term}
            ) ::
              map()

  @doc false
  def put(pubsub, doc_id, doc, field_keys) do
    {storage_module, storage_process_name} = storage_info(pubsub)

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

        result = storage_module.put(storage_process_name, doc_id, doc_value, field_keys)

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
    {storage_module, storage_process_name} = storage_info(pubsub)

    :telemetry.span(
      [:absinthe, :subscription, :storage, :delete],
      %{
        doc_id: doc_id,
        storage_module: storage_module
      },
      fn ->
        result = storage_module.delete(storage_process_name, doc_id)

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
    {storage_module, storage_process_name} = storage_info(pubsub)

    :telemetry.span(
      [:absinthe, :subscription, :storage, :get_docs_by_field_key],
      %{
        field_key: field_key,
        storage_module: storage_module
      },
      fn ->
        result =
          storage_process_name
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

  defp storage_info(pubsub) do
    storage_module = Subscription.document_storage(pubsub)
    storage_process_name = Subscription.document_storage_name(pubsub)
    {storage_module, storage_process_name}
  end
end
