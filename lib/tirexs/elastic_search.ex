defmodule Tirexs.ElasticSearch do

  @doc """
  This module provides a simple convenience for connection options such as `port`, `uri`, `user`, `pass`
  and functions for doing a `HTTP` request to `ElasticSearch` engine directly.
  """

  require Record
  require Logger

  Record.defrecord :record_config,  [port: 9200, uri: "127.0.0.1", user: nil, pass: nil]
  @number_of_retry 1
  @exponential_base 8

  @doc false
  def get(query_url, config) do
    call_then_tc_then_log(Tirexs.ElasticSearch, :do_request, [make_url(query_url, config), :get])
  end

  @doc false
  def put(query_url, config), do: put(query_url, [], config)

  def put(query_url, body, config) do
    unless body == [], do: body = to_string(body)
    call_then_tc_then_log(Tirexs.ElasticSearch, :do_request, [make_url(query_url, config), :put, body])
  end

  @doc false
  def delete(query_url, config), do: delete(query_url, [], config)

  @doc false
  def delete(query_url, _body, config) do
    unless _body == [], do: _body = to_string(_body)
    call_then_tc_then_log(Tirexs.ElasticSearch, :do_request, [make_url(query_url, config), :delete])
  end

  @doc false
  def head(query_url, config) do
    call_then_tc_then_log(Tirexs.ElasticSearch, :do_request, [make_url(query_url, config), :head])
  end

  @doc false
  def post(query_url, config), do: post(query_url, [], config)

  def post(query_url, body, config) do
    unless body == [], do: body = to_string(body)
    url = make_url(query_url, config)
    call_then_tc_then_log(Tirexs.ElasticSearch, :do_request, [url, :post, body])
  end

  @doc false
  def exist?(url, settings) do
    case head(url, settings) do
      {:error, _, _} -> false
      _ -> true
    end
  end

  # this complex method do call function with tc and log, similar to bukalapak/palaver
  def call_then_tc_then_log(module, function, params) do
    {time, reply} = :timer.tc(module, function, params)

    microseconds = rem(time, 1000)
    time = div(time, 1000)
    milliseconds = rem(time, 1000)
    time = div(time, 1000)
    seconds = rem(time, 1000)

    string_time = microseconds |> to_string()
    if ((seconds != 0) || (milliseconds != 0)), do: string_time = "#{milliseconds}_#{string_time |> String.rjust(3, ?0)}"
    if (seconds != 0), do: string_time = "#{seconds}_#{string_time |> String.rjust(7, ?0)}"

    last_module = module |> Module.split() |> Enum.at(-1)
    longest_length = "Room.load_unclosed_rooms_state_to_memory" |> String.length()
    last_module_and_function = "#{last_module}.#{function}" |> String.ljust(longest_length + 1)

    Logger.info("\t#{string_time}\t#{last_module_and_function}\t#{inspect(params)}")
    reply# return
  end

  @doc false
  def do_request(url, method, body \\ []) do
    do_request_with_retry(url, method, body, @number_of_retry)
  end


  defp do_request_with_retry(url, method, body, retry_left) do
    try do
      :inets.start()
      { url, content_type, options } = { String.to_char_list(url), 'application/json', [{:body_format, :binary}] }
      case method do
        :get    -> response(:httpc.request(method, {url, []}, [], []))
        :head   -> response(:httpc.request(method, {url, []}, [], []))
        :put    -> response(:httpc.request(method, {url, make_headers, content_type, body}, [], options))
        :post   -> response(:httpc.request(method, {url, make_headers, content_type, body}, [], options))
        :delete -> response(:httpc.request(method, {url, make_headers},[],[]))
      end
    rescue
      error ->
        if retry_left == 0 do
          Logger.error("#{inspect(error)} ==========> no more retry")
          raise error
        else
          Logger.error("#{inspect(error)} ==========> #{retry_left} retry(ies) left")
          sleep_duration = round(:math.pow(@exponential_base, (@number_of_retry - retry_left)))
          :timer.sleep(sleep_duration * 100)
          do_request_with_retry(url, method, body, retry_left - 1)
        end
    end
  end

  defp response(req) do
    case req do
      {:ok, { {_, status, _}, _, body}} ->
        if round(status / 100) == 4 || round(status / 100) == 5 do
          raise "#{inspect({ :error, status, body })}"
        else
          case body do
            [] -> { :ok, status, [] }
            "" -> { :ok, status, "" }
            "Published\n" -> { :ok, status, "Published\n" }
            _  -> { :ok, status, get_body_json(body) }
          end
        end
      error -> raise "#{inspect(error)}"
    end
  end

  def get_body_json(body), do: JSEX.decode!(to_string(body), [{:labels, :atom}])

  def make_url(query_url, config) do
    if (config |> record_config(:port) == nil) || (config |> record_config(:port)) == 80 do
      "http://#{config |> record_config(:uri)}/#{query_url}"
    else
      "http://#{config |> record_config(:uri)}:#{config |> record_config(:port)}/#{query_url}"
    end
  end

  defp make_headers, do: [{'Content-Type', 'application/json'}]
end
