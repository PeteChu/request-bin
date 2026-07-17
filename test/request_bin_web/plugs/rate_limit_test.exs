defmodule RequestBinWeb.Plugs.RateLimitTest do
  use RequestBinWeb.ConnCase

  import Plug.Test

  alias RequestBinWeb.Plugs.RateLimit

  setup do
    previous = Application.fetch_env!(:request_bin, :collector_rate_limit)
    on_exit(fn -> Application.put_env(:request_bin, :collector_rate_limit, previous) end)
    :ok
  end

  test "allows requests through the limit and denies the next request" do
    ip = {192, 0, 2, 41}
    opts = RateLimit.init(scale_ms: 60_000, limit: 2)

    first = limited_conn(ip, opts)
    second = limited_conn(ip, opts)
    denied = limited_conn(ip, opts)

    refute first.halted
    refute second.halted
    assert denied.halted
    assert denied.status == 429
    assert [retry_after] = Plug.Conn.get_resp_header(denied, "retry-after")
    assert {seconds, ""} = Integer.parse(retry_after)
    assert seconds >= 1
  end

  test "different client IPs use independent counters" do
    opts = RateLimit.init(scale_ms: 60_000, limit: 1)

    refute limited_conn({192, 0, 2, 42}, opts).halted
    assert limited_conn({192, 0, 2, 42}, opts).halted
    refute limited_conn({192, 0, 2, 43}, opts).halted
  end

  test "browser routes do not invoke the collector limiter", %{conn: conn} do
    Application.put_env(:request_bin, :collector_rate_limit, scale_ms: 60_000, limit: 1)

    first = get(conn, ~p"/")
    second = conn |> recycle() |> get(~p"/")

    assert redirected_to(first) == ~p"/bin"
    assert redirected_to(second) == ~p"/bin"
  end

  defp limited_conn(ip, opts) do
    conn(:get, "/bin/example")
    |> Map.put(:remote_ip, ip)
    |> RateLimit.call(opts)
  end
end
