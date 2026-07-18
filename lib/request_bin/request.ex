defmodule RequestBin.Requests do
  import Ecto.Query

  alias RequestBin.Repo
  alias RequestBin.Bins.Request
  alias RequestBin.RequestsRepo
  alias RequestBin.BinsRepo

  @type request_info :: %{
          host: String.t(),
          method: String.t(),
          path: String.t(),
          query_params: map(),
          remote_ip: String.t(),
          headers: map(),
          body_raw: binary(),
          body_parsed: map()
        }

  @spec extract_request_info(Plug.Conn.t()) ::
          {:ok, request_info()} | {:error, :body_not_captured}
  def extract_request_info(
        %Plug.Conn{
          query_params: query_params,
          host: host,
          remote_ip: remote_ip,
          req_headers: req_headers,
          request_path: request_path
        } = conn
      ) do
    with {:ok, raw_body} <- Map.fetch(conn.private, :request_bin_raw_body) do
      headers =
        format_headers(req_headers)
        |> Map.filter(fn {key, _value} ->
          !String.starts_with?(key, "fly-") ||
            !String.starts_with?(key, "x-") ||
            key != "via"
        end)

      request_info = %{
        host: host,
        method: Map.get(conn.private, :request_bin_original_method, conn.method),
        path: request_path,
        query_params: query_params,
        remote_ip: format_ip(remote_ip),
        headers: headers,
        body_raw: raw_body,
        body_parsed: parse_body(raw_body, Map.get(headers, "content-type"))
      }

      {:ok, request_info}
    else
      :error -> {:error, :body_not_captured}
    end
  end

  def process_request(request_info, params) do
    with {:ok, bin_id} <- Map.fetch(params, "id"), {:ok, _bin} <- get_bin(bin_id) do
      create_request(bin_id, request_info)
    else
      :error ->
        {:error, :invalid_params}

      {:error, :not_found} ->
        {:error, :bin_not_found}
    end
  end

  defp parse_body("", _content_type), do: %{}

  defp parse_body(body, content_type) when is_binary(body) do
    case media_type(content_type) do
      :json -> parse_json(body)
      :urlencoded -> parse_urlencoded(body)
      _other -> %{}
    end
  end

  defp parse_json(body) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) -> decoded
      {:ok, decoded} -> %{"_json" => decoded}
      {:error, _reason} -> %{"_parse_error" => "invalid_json"}
    end
  end

  defp parse_urlencoded(body) do
    Plug.Conn.Query.decode(body)
  rescue
    _error -> %{"_parse_error" => "invalid_urlencoded"}
  end

  defp media_type(content_type) when is_binary(content_type) do
    case Plug.Conn.Utils.content_type(content_type) do
      {:ok, "application", "x-www-form-urlencoded", _params} ->
        :urlencoded

      {:ok, "application", subtype, _params} ->
        if subtype == "json" or String.ends_with?(subtype, "+json"), do: :json, else: :other

      _other ->
        :other
    end
  end

  defp media_type(_content_type), do: :other

  defp format_ip(ip) when is_tuple(ip), do: :inet.ntoa(ip) |> to_string()
  defp format_ip(ip) when is_binary(ip), do: ip

  defp format_headers(headers) do
    headers
    |> Enum.into(%{}, fn {key, value} -> {key, value} end)
  end

  defp get_bin(bin_id) do
    case BinsRepo.get_bin(bin_id) do
      nil -> {:error, :not_found}
      bin -> {:ok, bin}
    end
  end

  def delete_for_bin(bin_id) do
    from(r in Request, where: r.bin_id == ^bin_id) |> Repo.delete_all()
  end

  def create_request(bin_id, request_info) do
    body_raw = if is_binary(request_info.body_raw), do: request_info.body_raw, else: ""
    body_parsed = if is_map(request_info.body_parsed), do: request_info.body_parsed, else: %{}

    result =
      RequestsRepo.create_request(%{
        path: request_info.path,
        ip: request_info.remote_ip,
        headers: request_info.headers,
        method: request_info.method,
        body_raw: body_raw,
        body_parsed: body_parsed,
        query_params: request_info.query_params,
        bin_id: bin_id
      })

    case result do
      {:ok, request} ->
        Phoenix.PubSub.broadcast(
          RequestBin.PubSub,
          "bin:#{request.bin_id}",
          {:new_request, request}
        )

        result

      _ ->
        result
    end
  end
end
