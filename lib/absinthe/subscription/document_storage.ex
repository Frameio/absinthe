defmodule Absinthe.Subscription.DocumentStorage do
  @moduledoc """
  Behaviour for storing subscription documents. Used to tell
  Absinthe how to store documents and the field keys subcribed to those
  documents.
  """
  alias Module.Behaviour

  @doc """
  Child spec to determine how to start the
  Document storage process
  """
  @callback child_spec(opts :: Keyword.t()) :: Supervisor.child_spec()

  @doc """
  Adds `doc` to storage with `doc_id` as the key if not already in storage. Also
  associates each `{field, key}` pair in `field_keys` to the `doc_id`
  """
  @callback subscribe(
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
  Removes the document and field_keys associated with `doc_id` from
  storage
  """
  @callback unsubscribe(pubsub :: atom, doc_id :: term) :: :ok

  @doc """
  Get all docs associated with the field_key
  """
  @callback get_docs_by_field_key(pubsub :: atom, field_key :: {field :: term, key :: term}) ::
              map()
end
