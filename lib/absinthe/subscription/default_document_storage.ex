defmodule Absinthe.Subscription.DefaultDocumentStorage do
  @behaviour Absinthe.Subscription.DocumentStorage

  @moduledoc """
  Default document storage for Absinthe. Stores subscription
  documents and field keys in a Registry.
  """

  @impl Absinthe.Subscription.DocumentStorage
  def child_spec(opts) do
    Registry.child_spec(opts)
  end

  @impl Absinthe.Subscription.DocumentStorage
  def put(storage_process_name, doc_id, doc_value, field_keys) do
    pdict_add_fields(doc_id, field_keys)

    for field_key <- field_keys do
      {:ok, _} = Registry.register(storage_process_name, field_key, doc_id)
    end

    {:ok, _} = Registry.register(storage_process_name, doc_id, doc_value)
  end

  @impl Absinthe.Subscription.DocumentStorage
  def delete(storage_process_name, doc_id) do
    for field_key <- pdict_fields(doc_id) do
      Registry.unregister(storage_process_name, field_key)
    end

    pdict_delete_fields(doc_id)

    Registry.unregister(storage_process_name, doc_id)

    :ok
  end

  @impl Absinthe.Subscription.DocumentStorage
  def get_docs_by_field_key(storage_process_name, field_key) do
    storage_process_name
    |> Registry.lookup(field_key)
    |> MapSet.new(fn {_pid, doc_id} -> doc_id end)
    |> Enum.reduce(%{}, fn doc_id, acc ->
      case Registry.lookup(storage_process_name, doc_id) do
        [] ->
          acc

        [{_pid, doc} | _rest] ->
          Map.put_new(acc, doc_id, doc)
      end
    end)
  end

  defp pdict_fields(doc_id) do
    Process.get({__MODULE__, doc_id}, [])
  end

  defp pdict_add_fields(doc_id, field_keys) do
    Process.put({__MODULE__, doc_id}, field_keys ++ pdict_fields(doc_id))
  end

  defp pdict_delete_fields(doc_id) do
    Process.delete({__MODULE__, doc_id})
  end
end
