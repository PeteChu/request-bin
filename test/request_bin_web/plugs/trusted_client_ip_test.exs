defmodule RequestBinWeb.Plugs.TrustedClientIpTest do
  use ExUnit.Case

  import Plug.Conn
  import Plug.Test

  alias RequestBinWeb.Plugs.TrustedClientIp

  @header "x-client-ip"

  setup do
    previous = Application.fetch_env!(:request_bin, :client_ip)
    on_exit(fn -> Application.put_env(:request_bin, :client_ip, previous) end)
    :ok
  end

  test "safe default accepts peer-only mode and preserves the peer" do
    configure(nil, [])
    assert :ok = TrustedClientIp.validate_config!()

    conn =
      conn(:get, "/")
      |> with_peer({192, 0, 2, 10})
      |> put_req_header(@header, "198.51.100.20")
      |> TrustedClientIp.call([])

    assert conn.remote_ip == {192, 0, 2, 10}
    assert conn.private.request_bin_peer_ip == {192, 0, 2, 10}
  end

  test "configuration requires both a header and CIDRs" do
    configure(nil, ["192.0.2.0/24"])

    assert_raise ArgumentError, ~r/header is required/, fn ->
      TrustedClientIp.validate_config!()
    end

    configure(@header, [])

    assert_raise ArgumentError, ~r/CIDRs are required/, fn ->
      TrustedClientIp.validate_config!()
    end
  end

  test "configuration rejects invalid headers and CIDRs" do
    configure("X Client IP", ["192.0.2.0/24"])

    assert_raise ArgumentError, ~r/valid lower-case HTTP field name/, fn ->
      TrustedClientIp.validate_config!()
    end

    configure(@header, ["not-a-cidr"])

    assert_raise ArgumentError, ~r/invalid trusted proxy CIDR/, fn ->
      TrustedClientIp.validate_config!()
    end
  end

  test "valid forwarded configuration passes validation" do
    configure(@header, ["192.0.2.0/24", "2001:db8::/32"])
    assert :ok = TrustedClientIp.validate_config!()
  end

  test "an untrusted peer cannot supply the client IP" do
    configure(@header, ["192.0.2.0/24"])

    conn =
      conn(:get, "/")
      |> with_peer({203, 0, 113, 10})
      |> put_req_header(@header, "198.51.100.20")
      |> TrustedClientIp.call([])

    assert conn.remote_ip == {203, 0, 113, 10}
    assert conn.private.request_bin_peer_ip == {203, 0, 113, 10}
  end

  test "trusted IPv4 and IPv6 peers can supply the client IP" do
    configure(@header, ["192.0.2.0/24", "2001:db8:1::/48"])

    ipv4_conn =
      conn(:get, "/")
      |> with_peer({192, 0, 2, 15})
      |> put_req_header(@header, "198.51.100.20")
      |> TrustedClientIp.call([])

    assert ipv4_conn.remote_ip == {198, 51, 100, 20}
    assert ipv4_conn.private.request_bin_peer_ip == {192, 0, 2, 15}

    ipv6_conn =
      conn(:get, "/")
      |> with_peer({0x2001, 0xDB8, 1, 0, 0, 0, 0, 15})
      |> put_req_header(@header, "2001:db8:ffff::20")
      |> TrustedClientIp.call([])

    assert ipv6_conn.remote_ip == {0x2001, 0xDB8, 0xFFFF, 0, 0, 0, 0, 0x20}
    assert ipv6_conn.private.request_bin_peer_ip == {0x2001, 0xDB8, 1, 0, 0, 0, 0, 15}
  end

  test "missing, duplicate, and malformed headers fail closed" do
    configure(@header, ["192.0.2.0/24"])
    peer = {192, 0, 2, 15}

    missing = conn(:get, "/") |> with_peer(peer) |> TrustedClientIp.call([])

    duplicate =
      conn(:get, "/")
      |> with_peer(peer)
      |> Map.put(:req_headers, [{@header, "198.51.100.20"}, {@header, "198.51.100.21"}])
      |> TrustedClientIp.call([])

    malformed =
      conn(:get, "/")
      |> with_peer(peer)
      |> put_req_header(@header, "not-an-ip")
      |> TrustedClientIp.call([])

    for result <- [missing, duplicate, malformed] do
      assert result.remote_ip == peer
      assert result.private.request_bin_peer_ip == peer
    end
  end

  defp configure(header, cidrs) do
    Application.put_env(:request_bin, :client_ip,
      header: header,
      trusted_proxy_cidrs: cidrs
    )
  end

  defp with_peer(conn, peer), do: %{conn | remote_ip: peer}
end
