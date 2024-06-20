defmodule Absinthe.Subscription.MutationPublishProcessor do
  @moduledoc """
  Processes the publish_mutation request on the
  local node.
  """

  def start_link({pubsub, mutation_result, subscribed_fields}) do
    Task.start_link(fn ->
      id = :erlang.unique_integer()
      system_time = System.system_time()
      start_time_mono = System.monotonic_time()

      :telemetry.execute(
        [:absinthe, :subscription, :publish_mutation, :start],
        %{system_time: system_time},
        %{
          id: id,
          telemetry_span_context: id,
          mutation_result: mutation_result,
          subscribed_fields: subscribed_fields
        }
      )

      try do
        Absinthe.Subscription.Local.publish_mutation(pubsub, mutation_result, subscribed_fields)
      after
        end_time_mono = System.monotonic_time()

        :telemetry.execute(
          [:absinthe, :subscription, :publish_mutation, :stop],
          %{duration: end_time_mono - start_time_mono, end_time_mono: end_time_mono},
          %{
            id: id,
            telemetry_span_context: id,
            mutation_result: mutation_result,
            subscribed_fields: subscribed_fields
          }
        )
      end
    end)
  end
end
