defmodule RequestBinWeb.Plugs.RequestCapture do
  @moduledoc """
  Captures bounded collector request bodies before the standard parsers consume them.
  """

  @behaviour Plug

  require Logger

  import Plug.Conn

  @collector_methods ~w(GET HEAD POST PUT PATCH DELETE)
  @max_read_length 1_000_000

  @impl Plug
  def init(opts), do: Plug.Parsers.init(opts)

  @impl Plug
  def call(conn, parser_opts) do
    if collector_request?(conn) do
      capture(conn)
    else
      Plug.Parsers.call(conn, parser_opts)
    end
  end

  defp collector_request?(%Plug.Conn{path_info: ["bin", id], method: method}) do
    id != "" and method in @collector_methods
  end

  defp collector_request?(_conn), do: false

  defp capture(conn) do
    max_body_bytes =
      :request_bin
      |> Application.fetch_env!(:request_capture)
      |> Keyword.fetch!(:max_body_bytes)

    conn =
      conn
      |> put_private(:request_bin_original_method, conn.method)
      |> put_private(:request_bin_collector, true)
      |> fetch_query_params()

    case read_body(conn,
           length: max_body_bytes,
           read_length: min(max_body_bytes, @max_read_length),
           read_timeout: 15_000
         ) do
      {:ok, body, conn} -> prepare_collector_params(conn, body)
      {:more, _partial, conn} -> respond_and_halt(conn, 413, "request body too large")
      {:error, :timeout} -> respond_and_halt(conn, 408, "request body read timed out")
      {:error, reason} -> handle_read_error(conn, reason)
    end
  end

  defp prepare_collector_params(conn, body) do
    query_params = conn.query_params

    %{
      conn
      | body_params: %{},
        params: query_params,
        private: Map.put(conn.private, :request_bin_raw_body, body)
    }
  end

  defp handle_read_error(conn, reason) do
    Logger.warning("collector body read failed: #{read_error_label(reason)}")
    respond_and_halt(conn, 400, "could not read request body")
  end

  defp read_error_label(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp read_error_label(%{__struct__: module}), do: inspect(module)
  defp read_error_label(_reason), do: "unknown"

  defp respond_and_halt(conn, status, message) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(status, message)
    |> halt()
  end
end
