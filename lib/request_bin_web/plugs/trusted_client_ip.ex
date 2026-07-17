defmodule RequestBinWeb.Plugs.TrustedClientIp do
  @moduledoc """
  Uses a configured forwarding header only when the socket peer is trusted.
  """

  @behaviour Plug

  alias RequestBin.Network.CIDR

  @http_field_name ~r/^[!#$%&'*+\-.^_`|~0-9a-z]+$/

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    peer_ip = conn.remote_ip
    conn = Plug.Conn.put_private(conn, :request_bin_peer_ip, peer_ip)

    case validated_config!() do
      :peer_only ->
        conn

      {:forwarded, header, cidrs} ->
        maybe_use_forwarded_ip(conn, peer_ip, header, cidrs)
    end
  end

  @spec validate_config!() :: :ok
  def validate_config! do
    _validated_config = validated_config!()
    :ok
  end

  defp validated_config! do
    config = Application.fetch_env!(:request_bin, :client_ip)
    header = Keyword.get(config, :header)
    cidr_strings = Keyword.get(config, :trusted_proxy_cidrs, [])

    case {header, cidr_strings} do
      {nil, []} ->
        :peer_only

      {nil, cidrs} when is_list(cidrs) and cidrs != [] ->
        raise ArgumentError,
              "client IP header is required when trusted proxy CIDRs are configured"

      {configured_header, []} when is_binary(configured_header) ->
        raise ArgumentError,
              "trusted proxy CIDRs are required when a client IP header is configured"

      {configured_header, cidrs} when is_binary(configured_header) and is_list(cidrs) ->
        validate_header!(configured_header)
        {:forwarded, configured_header, Enum.map(cidrs, &parse_cidr!/1)}

      _other ->
        raise ArgumentError, "invalid client IP configuration"
    end
  end

  defp validate_header!(header) do
    if header != String.downcase(header) or not Regex.match?(@http_field_name, header) do
      raise ArgumentError, "client IP header must be a valid lower-case HTTP field name"
    end
  end

  defp parse_cidr!(cidr) when is_binary(cidr) do
    case CIDR.parse(cidr) do
      {:ok, parsed} -> parsed
      {:error, _reason} -> raise ArgumentError, "invalid trusted proxy CIDR: #{inspect(cidr)}"
    end
  end

  defp parse_cidr!(cidr) do
    raise ArgumentError, "invalid trusted proxy CIDR: #{inspect(cidr)}"
  end

  defp maybe_use_forwarded_ip(conn, peer_ip, header, cidrs) do
    if Enum.any?(cidrs, &CIDR.contains?(&1, peer_ip)) do
      case Plug.Conn.get_req_header(conn, header) do
        [value] -> adopt_valid_ip(conn, RemoteIp.from([{header, value}], headers: [header]))
        _missing_or_duplicate -> conn
      end
    else
      conn
    end
  end

  defp adopt_valid_ip(conn, ip) when is_tuple(ip) and tuple_size(ip) in [4, 8] do
    %{conn | remote_ip: ip}
  end

  defp adopt_valid_ip(conn, _invalid_ip), do: conn
end
