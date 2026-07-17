defmodule RequestBin.Network.CIDR do
  @moduledoc """
  Parses and matches IPv4 and IPv6 CIDR ranges.
  """

  import Bitwise

  @opaque t :: {4 | 6, non_neg_integer(), 0..128}

  @spec parse(String.t()) :: {:ok, t()} | {:error, atom()}
  def parse(value) when is_binary(value) do
    with [address, prefix] <- String.split(value, "/", parts: 2),
         {:ok, ip} <- parse_address(address),
         {:ok, prefix_length} <- parse_prefix(prefix, ip) do
      bits = address_bits(ip)
      mask = prefix_mask(prefix_length, bits)
      {:ok, {family(ip), address_to_integer(ip) &&& mask, prefix_length}}
    else
      [_address] -> parse_bare_address(value)
      {:error, reason} -> {:error, reason}
      _other -> {:error, :invalid_cidr}
    end
  end

  def parse(_value), do: {:error, :invalid_cidr}

  @spec contains?(t(), :inet.ip_address()) :: boolean()
  def contains?({cidr_family, network, prefix_length}, ip) when is_tuple(ip) do
    if valid_ip?(ip) and family(ip) == cidr_family do
      mask = prefix_mask(prefix_length, address_bits(ip))
      (address_to_integer(ip) &&& mask) == network
    else
      false
    end
  end

  def contains?(_cidr, _ip), do: false

  defp parse_bare_address(address) do
    with {:ok, ip} <- parse_address(address) do
      prefix_length = address_bits(ip)
      {:ok, {family(ip), address_to_integer(ip), prefix_length}}
    end
  end

  defp parse_address(address) do
    case :inet.parse_strict_address(String.to_charlist(address)) do
      {:ok, ip} -> {:ok, ip}
      {:error, _reason} -> {:error, :invalid_address}
    end
  end

  defp parse_prefix(prefix, ip) do
    max_prefix = address_bits(ip)

    case Integer.parse(prefix) do
      {value, ""} when value >= 0 and value <= max_prefix -> {:ok, value}
      {_, ""} -> {:error, :prefix_out_of_range}
      _other -> {:error, :invalid_prefix}
    end
  end

  defp valid_ip?(ip) do
    tuple_size(ip) in [4, 8] and
      ip
      |> Tuple.to_list()
      |> Enum.all?(&(is_integer(&1) and &1 >= 0 and &1 <= 65_535)) and
      (tuple_size(ip) == 8 or Enum.all?(Tuple.to_list(ip), &(&1 <= 255)))
  end

  defp family(ip) when tuple_size(ip) == 4, do: 4
  defp family(ip) when tuple_size(ip) == 8, do: 6

  defp address_bits(ip) when tuple_size(ip) == 4, do: 32
  defp address_bits(ip) when tuple_size(ip) == 8, do: 128

  defp address_to_integer(ip) do
    segment_bits = if tuple_size(ip) == 4, do: 8, else: 16

    Enum.reduce(Tuple.to_list(ip), 0, fn segment, integer ->
      (integer <<< segment_bits) + segment
    end)
  end

  defp prefix_mask(0, _bits), do: 0

  defp prefix_mask(prefix_length, bits),
    do: ((1 <<< prefix_length) - 1) <<< (bits - prefix_length)
end
