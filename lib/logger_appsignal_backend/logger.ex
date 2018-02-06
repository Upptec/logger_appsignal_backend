defmodule LoggerAppsignalBackend.Logger do
  @moduledoc false

  @default_format "$message"
  @standard_metadata  [:module, :function, :file, :line]
  @all_metadata       [:pid | @standard_metadata]

  @behaviour :gen_event

  defstruct device: nil,
            format: nil,
            metadata: nil

  def init(__MODULE__) do
    config = Application.get_env(:logger, :logger_appsignal_backend) || []
    device = Keyword.get(config, :device, :user)

    if Process.whereis(device) do
      {:ok, init(config, %__MODULE__{})}
    else
      {:error, :ignore}
    end
  end

  def init({__MODULE__, opts}) when is_list(opts) do
    config = configure_merge(Application.get_env(:logger, :logger_appsignal_backend), opts)
    {:ok, init(config, %__MODULE__{})}
  end

  def handle_call({:configure, options}, state) do
    {:ok, :ok, configure(options, state)}
  end

  def handle_event({_level, gl, _event}, state) when node(gl) != node() do
    {:ok, state}
  end

  def handle_event({:error, _gl, {Logger, msg, ts, md}}, state) do
    {:ok, log_event(:error, msg, ts, md, state)}
  end

  def handle_event(_, state) do
    {:ok, state}
  end

  def handle_info(_, state) do
    {:ok, state}
  end

  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end

  def terminate(_reason, _state) do
    :ok
  end

  ## Helpers

  defp configure(options, state) do
    config = configure_merge(Application.get_env(:logger, :logger_appsignal_backend), options)
    Application.put_env(:logger, :logger_appsignal_backend, config)
    init(config, state)
  end

  defp init(config, state) do
    device = Keyword.get(config, :device, :user)
    format = Logger.Formatter.compile(Keyword.get(config, :format, @default_format))
    metadata = Keyword.get(config, :metadata, @standard_metadata) |> configure_metadata()

    %{
      state
      | format: format,
        metadata: metadata,
        device: device
    }
  end

  defp configure_metadata(:all), do: :all
  defp configure_metadata(metadata), do: Enum.reverse(metadata)

  defp configure_merge(env, options) do
    Keyword.merge(env, options, fn
      :colors, v1, v2 -> Keyword.merge(v1, v2)
      _, _v1, v2 -> v2
    end)
  end

  defp log_event(level, msg, ts, md, state) do
    %{metadata: keys} = state
    output = format_event(level, msg, ts, md, state)
    |> List.to_string()
    |> remove_pid()

    metadata_to_send =
      md
      |> take_metadata(keys)
      |> Map.new()

    tags = md |> extract_extra_tags()
    trans_fun = fn(transaction) ->
      Appsignal.Transaction.set_sample_data(transaction, "session_data", tags)
    end
    namespace = Keyword.get(md, :namespace, :background)
    stacktrace = get_stacktrace(md)
    # https://github.com/appsignal/appsignal-elixir/blob/develop/lib/appsignal.ex
    msg
    |> remove_pid()
    |> Appsignal.send_error(output, stacktrace, metadata_to_send, nil, trans_fun, namespace)

    state
  end

  defp format_event(level, msg, ts, md, state) do
    %{format: format, metadata: keys} = state

    format
    |> Logger.Formatter.format(level, msg, ts, take_metadata(md, keys))
  end

  defp take_metadata(metadata, :all), do: metadata

  defp take_metadata(metadata, keys) do
    Enum.reduce(keys, [], fn key, acc ->
      case Keyword.fetch(metadata, key) do
        {:ok, val} -> [{key, val} | acc]
        :error -> acc
      end
    end)
  end

  defp get_stacktrace(md) when is_list(md), do: get_stacktrace(Map.new(md))
  defp get_stacktrace(%{pid: pid}) do
    case Process.info(pid, :current_stacktrace) do
      {_, stacktrace} -> stacktrace
      _ -> nil
    end
  end
  defp get_stacktrace(_), do: nil

  defp remove_pid(msg) when is_binary(msg) do
    r = ~r/#PID<\d+\.\d+\.\d+>/
    String.replace(msg, r, "#PID<removed>")
  end
  defp remove_pid(msg), do: msg

  defp extract_extra_tags(md) when is_list(md) do
    md
    |> Map.new
    |> Map.drop(@all_metadata)
    |> Map.drop([:namespace])
    |> clean_extra_tags()
  end
  defp extract_extra_tags(%{} = sample), do: sample |> clean_extra_tags()
  defp extract_extra_tags(_), do: %{}

  defp clean_extra_tags(metadata) do
    metadata
    |> Enum.reduce(Map.new(), &clean_extra_tags/2)
  end
  defp clean_extra_tags({key, value}, acc) when (is_binary(value) or is_number(value) or is_atom(value)) and (is_atom(key) or is_binary(key)) do
    Map.put(acc, key, value)
  end
  defp clean_extra_tags(_,acc), do: acc
end
