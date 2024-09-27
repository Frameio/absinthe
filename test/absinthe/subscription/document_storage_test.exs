defmodule Absinthe.Subscription.DocumentStorageTest do
  use Absinthe.Case

  defmodule TestDocumentStorageSchema do
    use Absinthe.Schema

    query do
      field :foo, :string
    end

    object :user do
      field :id, :id
      field :name, :string

      field :group, :group do
        resolve fn user, _, %{context: %{test_pid: pid}} ->
          batch({__MODULE__, :batch_get_group, pid}, nil, fn _results ->
            {:ok, user.group}
          end)
        end
      end
    end

    object :group do
      field :name, :string
    end

    def batch_get_group(test_pid, _) do
      # send a message to the test process every time we access this function.
      # if batching is working properly, it should only happen once.
      send(test_pid, :batch_get_group)
      %{}
    end

    subscription do
      field :raises, :string do
        config fn _, _ ->
          {:ok, topic: "*"}
        end

        resolve fn _, _, _ ->
          raise "boom"
        end
      end

      field :user, :user do
        arg :id, :id

        config fn args, _ ->
          {:ok, topic: args[:id] || "*"}
        end

        trigger :update_user,
          topic: fn user ->
            [user.id, "*"]
          end
      end

      field :thing, :string do
        arg :client_id, non_null(:id)

        config fn
          _args, %{context: %{authorized: false}} ->
            {:error, "unauthorized"}

          args, _ ->
            {
              :ok,
              topic: args.client_id
            }
        end
      end

      field :multiple_topics, :string do
        config fn _, _ ->
          {:ok, topic: ["topic_1", "topic_2", "topic_3"]}
        end
      end

      field :other_user, :user do
        arg :id, :id

        config fn
          args, %{context: %{context_id: context_id, document_id: document_id}} ->
            {:ok, topic: args[:id] || "*", context_id: context_id, document_id: document_id}

          args, %{context: %{context_id: context_id}} ->
            {:ok, topic: args[:id] || "*", context_id: context_id}
        end
      end

      field :relies_on_document, :string do
        config fn _, %{document: %Absinthe.Blueprint{} = document} ->
          %{type: :subscription, name: op_name} = Absinthe.Blueprint.current_operation(document)
          {:ok, topic: "*", context_id: "*", document_id: op_name}
        end
      end
    end

    mutation do
      field :update_user, :user do
        arg :id, non_null(:id)

        resolve fn _, %{id: id}, _ ->
          {:ok, %{id: id, name: "foo"}}
        end
      end
    end
  end

  defmodule TestDocumentStoragePubSub do
    @behaviour Absinthe.Subscription.Pubsub

    def start_link() do
      Registry.start_link(keys: :duplicate, name: __MODULE__)
    end

    def node_name() do
      node()
    end

    def subscribe(topic) do
      Registry.register(__MODULE__, topic, [])
      :ok
    end

    def publish_subscription(topic, data) do
      message = %{
        topic: topic,
        event: "subscription:data",
        result: data
      }

      Registry.dispatch(__MODULE__, topic, fn entries ->
        for {pid, _} <- entries, do: send(pid, {:broadcast, message})
      end)
    end

    def publish_mutation(_proxy_topic, _mutation_result, _subscribed_fields) do
      # this pubsub is local and doesn't support clusters
      :ok
    end
  end

  defmodule TestDocumentStorage do
    @behaviour Absinthe.Subscription.DocumentStorage
    use GenServer

    def start_link(_) do
      GenServer.start_link(__MODULE__, nil, name: __MODULE__)
    end

    @impl GenServer
    def init(_) do
      {:ok, %{docs: %{}, field_keys: %{}}}
    end

    @impl GenServer
    def handle_cast({:put, doc_id, doc_value, field_keys}, %{
          docs: docs,
          field_keys: field_keys_map
        }) do
      docs = Map.put_new(docs, doc_id, doc_value)

      field_keys_map =
        Enum.reduce(field_keys, field_keys_map, fn field_key, field_keys_map ->
          Map.update(field_keys_map, field_key, [doc_id], fn doc_ids -> [doc_id | doc_ids] end)
        end)

      {:noreply, %{docs: docs, field_keys: field_keys_map}}
    end

    @impl GenServer
    def handle_cast({:delete, doc_id}, %{
          docs: docs,
          field_keys: field_keys_map
        }) do
      docs = Map.delete(docs, doc_id)

      field_keys_map =
        Enum.map(field_keys_map, fn {field_key, doc_ids} ->
          doc_ids = List.delete(doc_ids, doc_id)
          {field_key, doc_ids}
        end)
        |> Map.new()

      {:noreply, %{docs: docs, field_keys: field_keys_map}}
    end

    @impl GenServer
    def handle_call(
          {:get_docs_by_field_key, field_key},
          _from,
          %{
            docs: docs,
            field_keys: field_keys_map
          } = state
        ) do
      doc_ids = Map.get(field_keys_map, field_key, [])

      docs_to_return =
        docs
        |> Enum.filter(fn {doc_id, _} -> doc_id in doc_ids end)
        |> Map.new()

      {:reply, docs_to_return, state}
    end

    @impl Absinthe.Subscription.DocumentStorage
    def put(_pubsub, doc_id, doc_value, field_keys) do
      GenServer.cast(__MODULE__, {:put, doc_id, doc_value, field_keys})
      :ok
    end

    @impl Absinthe.Subscription.DocumentStorage
    def delete(_pubsub, doc_id) do
      GenServer.cast(__MODULE__, {:delete, doc_id})

      :ok
    end

    @impl Absinthe.Subscription.DocumentStorage
    def get_docs_by_field_key(_pubsub, field_key) do
      GenServer.call(__MODULE__, {:get_docs_by_field_key, field_key})
    end
  end

  def run_subscription(query, schema, opts \\ []) do
    opts =
      Keyword.update(
        opts,
        :context,
        %{pubsub: TestDocumentStoragePubSub},
        &Map.put(&1, :pubsub, opts[:context][:pubsub] || TestDocumentStoragePubSub)
      )

    case run(query, schema, opts) do
      {:ok, %{"subscribed" => topic}} = val ->
        opts[:context][:pubsub].subscribe(topic)
        val

      val ->
        val
    end
  end

  setup do
    start_supervised(TestDocumentStorage)

    start_supervised(%{
      id: TestDocumentStoragePubSub,
      start: {TestDocumentStoragePubSub, :start_link, []}
    })

    start_supervised(
      {Absinthe.Subscription, pubsub: TestDocumentStoragePubSub, storage: TestDocumentStorage}
    )

    :ok
  end

  @query """
  subscription ($clientId: ID!) {
    thing(clientId: $clientId)
  }
  """
  test "can subscribe the current process" do
    client_id = "abc"

    assert {:ok, %{"subscribed" => topic}} =
             run_subscription(
               @query,
               TestDocumentStorageSchema,
               variables: %{"clientId" => client_id},
               context: %{pubsub: TestDocumentStoragePubSub}
             )

    Absinthe.Subscription.publish(TestDocumentStoragePubSub, "foo", thing: client_id)

    assert_receive({:broadcast, msg})

    assert %{
             event: "subscription:data",
             result: %{data: %{"thing" => "foo"}},
             topic: topic
           } == msg
  end

  @query """
  subscription ($clientId: ID!) {
    thing(clientId: $clientId)
  }
  """
  test "can unsubscribe the current process" do
    client_id = "abc"

    assert {:ok, %{"subscribed" => topic}} =
             run_subscription(
               @query,
               TestDocumentStorageSchema,
               variables: %{"clientId" => client_id},
               context: %{pubsub: TestDocumentStoragePubSub}
             )

    Absinthe.Subscription.unsubscribe(TestDocumentStoragePubSub, topic)

    Absinthe.Subscription.publish(TestDocumentStoragePubSub, "foo", thing: client_id)

    refute_receive({:broadcast, _})
  end

  @query """
  subscription {
    multipleTopics
  }
  """
  test "schema can provide multiple topics to subscribe to" do
    assert {:ok, %{"subscribed" => topic}} =
             run_subscription(
               @query,
               TestDocumentStorageSchema,
               variables: %{},
               context: %{pubsub: TestDocumentStoragePubSub}
             )

    msg = %{
      event: "subscription:data",
      result: %{data: %{"multipleTopics" => "foo"}},
      topic: topic
    }

    Absinthe.Subscription.publish(TestDocumentStoragePubSub, "foo", multiple_topics: "topic_1")

    assert_receive({:broadcast, ^msg})

    Absinthe.Subscription.publish(TestDocumentStoragePubSub, "foo", multiple_topics: "topic_2")

    assert_receive({:broadcast, ^msg})

    Absinthe.Subscription.publish(TestDocumentStoragePubSub, "foo", multiple_topics: "topic_3")

    assert_receive({:broadcast, ^msg})
  end

  @query """
  subscription {
    multipleTopics
  }
  """
  test "unsubscription works when multiple topics are provided" do
    assert {:ok, %{"subscribed" => topic}} =
             run_subscription(
               @query,
               TestDocumentStorageSchema,
               variables: %{},
               context: %{pubsub: TestDocumentStoragePubSub}
             )

    Absinthe.Subscription.unsubscribe(TestDocumentStoragePubSub, topic)

    Absinthe.Subscription.publish(TestDocumentStoragePubSub, "foo", multiple_topics: "topic_1")

    refute_receive({:broadcast, _})

    Absinthe.Subscription.publish(TestDocumentStoragePubSub, "foo", multiple_topics: "topic_2")

    refute_receive({:broadcast, _})

    Absinthe.Subscription.publish(TestDocumentStoragePubSub, "foo", multiple_topics: "topic_3")

    refute_receive({:broadcast, _})
  end
end
