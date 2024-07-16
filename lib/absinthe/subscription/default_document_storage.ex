defmodule Absinthe.Subscription.DefaultDocumentStorage do
  @behaviour Absinthe.Subscription.DocumentStorage
  @moduledoc """
  Default document storage for Absinthe. Stores subscription
  documents and field keys in a Registry.
  """

  alias Absinthe.Subscription

  @impl Absinthe.Subscription.DocumentStorage
  def put(pubsub, doc_id, doc_value, field_keys) do
    registry = Subscription.registry_name(pubsub)

    pdict_add_fields(doc_id, field_keys)

    for field_key <- field_keys do
      {:ok, _} = Registry.register(registry, field_key, doc_id)
    end

    {:ok, _} = Registry.register(registry, doc_id, doc_value)
  end

  @impl Absinthe.Subscription.DocumentStorage
  def delete(pubsub, doc_id) do
    registry = Subscription.registry_name(pubsub)

    for field_key <- pdict_fields(doc_id) do
      Registry.unregister(registry, field_key)
    end

    pdict_delete_fields(doc_id)

    Registry.unregister(registry, doc_id)

    :ok
  end

  @impl Absinthe.Subscription.DocumentStorage
  def get_docs_by_field_key(pubsub, field_key) do
    registry = Subscription.registry_name(pubsub)

    registry
    |> Registry.lookup(field_key)
    |> MapSet.new(fn {_pid, doc_id} -> doc_id end)
    |> Enum.reduce(%{}, fn doc_id, acc ->
      case Registry.lookup(registry, doc_id) do
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
