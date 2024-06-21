defmodule Absinthe.Subscription.DocumentStorage do
  @moduledoc """
  Behaviour for storing subscription documents. Used to tell
  Absinthe how to store documents and the field keys associated with those
  documents.
  """

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
end
