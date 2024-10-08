defmodule Absinthe.Phase.Document.Result do
  @moduledoc false

  # Produces data fit for external encoding from annotated value tree

  alias Absinthe.{Blueprint, Phase, Type}
  use Absinthe.Phase

  @spec run(Blueprint.t() | Phase.Error.t(), Keyword.t()) :: {:ok, map}
  def run(%Blueprint{} = bp, options \\ []) do
    result = Map.merge(bp.result, process(bp, options))
    {:ok, %{bp | result: result}}
  end

  defp process(blueprint, opts) do
    result =
      case blueprint.execution do
        %{validation_errors: [], result: nil} ->
          {:ok, data(%{value: nil}, [])}

        %{validation_errors: [], result: result} ->
          {:ok, data(result, [])}

        %{validation_errors: errors} ->
          {:validation_failed, errors}
      end

    format_result(result, opts)
  end

  defp format_result({:ok, {data, []}}, _) do
    %{data: data}
  end

  defp format_result({:ok, {data, errors}}, opts) do
    errors = errors |> Enum.uniq() |> Enum.map(&format_error(&1, opts))
    %{data: data, errors: errors}
  end

  defp format_result({:validation_failed, errors}, opts) do
    errors = errors |> Enum.uniq() |> Enum.map(&format_error(&1, opts))
    %{errors: errors}
  end

  defp data(%{errors: [_ | _] = field_errors}, errors), do: {nil, field_errors ++ errors}

  # Leaf
  defp data(%{value: nil}, errors), do: {nil, errors}

  defp data(%{value: value, emitter: emitter}, errors) do
    value =
      case Type.unwrap(emitter.schema_node.type) do
        %Type.Scalar{} = schema_node ->
          try do
            Type.Scalar.serialize(schema_node, value)
          rescue
            _e in [Absinthe.SerializationError, Protocol.UndefinedError] ->
              raise(
                Absinthe.SerializationError,
                """
                Could not serialize term #{inspect(value)} as type #{schema_node.name}

                When serializing the field:
                #{emitter.parent_type.name}.#{emitter.schema_node.name} (#{emitter.schema_node.__reference__.location.file}:#{emitter.schema_node.__reference__.location.line})
                """
              )
          end

        %Type.Enum{} = schema_node ->
          Type.Enum.serialize(schema_node, value)
      end

    {value, errors}
  end

  # Object
  defp data(%{fields: fields}, errors), do: field_data(fields, errors)

  # List
  defp data(%{values: values}, errors), do: list_data(values, errors)

  defp list_data(fields, errors, acc \\ [])
  defp list_data([], errors, acc), do: {:lists.reverse(acc), errors}

  defp list_data([%{errors: errs} = field | fields], errors, acc) do
    {value, errors} = data(field, errors)
    list_data(fields, errs ++ errors, [value | acc])
  end

  defp field_data(fields, errors, acc \\ [])
  defp field_data([], errors, acc), do: {Map.new(acc), errors}

  defp field_data([%Absinthe.Resolution{} = res | _], _errors, _acc) do
    raise """
    Found unresolved resolution struct!

    You probably forgot to run the resolution phase again.

    #{inspect(res)}
    """
  end

  defp field_data([field | fields], errors, acc) do
    {value, errors} = data(field, errors)
    field_data(fields, errors, [{field_name(field.emitter), value} | acc])
  end

  defp field_name(%{alias: nil, name: name}), do: name
  defp field_name(%{alias: name}), do: name
  defp field_name(%{name: name}), do: name

  defp format_error(%Phase.Error{message: %{message: _message} = error_object} = error, _opts) do
    if Enum.empty?(error.locations) do
      error_object
    else
      locations = Enum.flat_map(error.locations, &format_location/1)
      Map.put_new(error_object, :locations, locations)
    end
  end

  defp format_error(%Phase.Error{locations: []} = error, opts) do
    error_object = %{message: error.message}

    merge_error_extensions(error_object, error.extra, opts)
  end

  defp format_error(%Phase.Error{} = error, opts) do
    error_object = %{
      message: error.message,
      locations: Enum.flat_map(error.locations, &format_location/1)
    }

    error_object =
      case error.path do
        [] -> error_object
        path -> Map.put(error_object, :path, path)
      end

    merge_error_extensions(error_object, error.extra, opts)
  end

  defp merge_error_extensions(error_object, extra, _opts) when extra == %{} do
    error_object
  end

  defp merge_error_extensions(error_object, extra, opts) do
    if opts[:spec_compliant_errors] do
      Map.merge(%{extensions: extra}, error_object)
    else
      Map.merge(extra, error_object)
    end
  end

  defp format_location(%{line: line, column: col}) do
    [%{line: line || 0, column: col || 0}]
  end

  defp format_location(_), do: []
end
