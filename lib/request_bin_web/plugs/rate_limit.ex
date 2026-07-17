defmodule RequestBinWeb.Plugs.RateLimit do
  @moduledoc """
  Applies the collector request rate limit per validated client IP.
  """

  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts) do
    defaults = Application.fetch_env!(:request_bin, :collector_rate_limit)
    scale_ms = Keyword.get(opts, :scale_ms, Keyword.fetch!(defaults, :scale_ms))
    limit = Keyword.get(opts, :limit, Keyword.fetch!(defaults, :limit))
    key = "collector_requests:#{:inet.ntoa(conn.remote_ip)}"

    case RequestBin.RateLimit.hit(key, scale_ms, limit) do
      {:allow, _count} ->
        conn

      {:deny, retry_after_ms} ->
        retry_after_seconds = max(1, div(retry_after_ms + 999, 1000))

        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after_seconds))
        |> send_resp(429, "")
        |> halt()
    end
  end
end
