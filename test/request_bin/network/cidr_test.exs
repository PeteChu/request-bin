defmodule RequestBin.Network.CIDRTest do
  use ExUnit.Case, async: true

  alias RequestBin.Network.CIDR

  test "bare IPv4 and IPv6 addresses match exactly" do
    assert {:ok, ipv4} = CIDR.parse("192.0.2.10")
    assert CIDR.contains?(ipv4, {192, 0, 2, 10})
    refute CIDR.contains?(ipv4, {192, 0, 2, 11})

    assert {:ok, ipv6} = CIDR.parse("2001:db8::10")
    assert CIDR.contains?(ipv6, {0x2001, 0xDB8, 0, 0, 0, 0, 0, 0x10})
    refute CIDR.contains?(ipv6, {0x2001, 0xDB8, 0, 0, 0, 0, 0, 0x11})
  end

  test "matches IPv4 /24 membership" do
    assert {:ok, cidr} = CIDR.parse("192.0.2.0/24")
    assert CIDR.contains?(cidr, {192, 0, 2, 200})
    refute CIDR.contains?(cidr, {192, 0, 3, 1})
  end

  test "matches IPv6 /64 membership" do
    assert {:ok, cidr} = CIDR.parse("2001:db8:abcd:12::/64")
    assert CIDR.contains?(cidr, {0x2001, 0xDB8, 0xABCD, 0x12, 0, 0, 0, 1})
    refute CIDR.contains?(cidr, {0x2001, 0xDB8, 0xABCD, 0x13, 0, 0, 0, 1})
  end

  test "supports prefix boundaries" do
    assert {:ok, all_ipv4} = CIDR.parse("203.0.113.20/0")
    assert CIDR.contains?(all_ipv4, {198, 51, 100, 1})

    assert {:ok, exact_ipv4} = CIDR.parse("203.0.113.20/32")
    assert CIDR.contains?(exact_ipv4, {203, 0, 113, 20})
    refute CIDR.contains?(exact_ipv4, {203, 0, 113, 21})

    assert {:ok, exact_ipv6} = CIDR.parse("2001:db8::1/128")
    assert CIDR.contains?(exact_ipv6, {0x2001, 0xDB8, 0, 0, 0, 0, 0, 1})
    refute CIDR.contains?(exact_ipv6, {0x2001, 0xDB8, 0, 0, 0, 0, 0, 2})
  end

  test "family mismatches do not match" do
    assert {:ok, ipv4} = CIDR.parse("0.0.0.0/0")
    assert {:ok, ipv6} = CIDR.parse("::/0")
    refute CIDR.contains?(ipv4, {0, 0, 0, 0, 0, 0, 0, 1})
    refute CIDR.contains?(ipv6, {192, 0, 2, 1})
  end

  test "rejects invalid addresses and prefixes" do
    assert {:error, :invalid_address} = CIDR.parse("192.0.2.999")
    assert {:error, :invalid_prefix} = CIDR.parse("192.0.2.1/nope")
    assert {:error, :prefix_out_of_range} = CIDR.parse("192.0.2.1/33")
    assert {:error, :prefix_out_of_range} = CIDR.parse("2001:db8::1/129")
  end
end
