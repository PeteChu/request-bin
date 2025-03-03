defmodule RequestBin.Requests do
  import Ecto.Query

  alias RequestBin.Repo
  alias RequestBin.Bins.Request
  alias RequestBin.RequestsRepo
  alias RequestBin.BinsRepo

  require Logger

  def extract_request_info(
        %Plug.Conn{
          body_params: body_params,
          query_params: query_params,
          host: host,
          method: method,
          remote_ip: remote_ip,
          req_headers: req_headers,
          request_path: request_path
        } = conn
      ) do
    headers = format_headers(req_headers)

    # Read raw body first
    {:ok, raw_body, _conn} = Plug.Conn.read_body(conn)

    parsed_body =
      case {Map.get(headers, "content-type"), raw_body} do
        {content_type, body} when is_binary(body) and byte_size(body) > 0 ->
          cond do
            String.contains?(content_type || "", "application/json") ->
              case Jason.decode(body) do
                {:ok, parsed} -> parsed
                _ -> body
              end

            String.contains?(content_type || "", "multipart/form-data") ->
              body_params

            true ->
              body
          end

        _ ->
          body_params
      end

    request_info = %{
      host: host,
      method: method,
      path: request_path,
      query_params: query_params,
      remote_ip: format_ip(remote_ip),
      headers: headers,
      body: parsed_body,
      body_raw: raw_body
    }

    {:ok, request_info}
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
    formatted_body_raw =
      case request_info.body_raw do
        nil -> ""
        body when is_binary(body) -> body
        body -> inspect(body)
      end

    # Ensure body_parsed is properly formatted for storage
    formatted_body_parsed =
      case request_info.body do
        body when is_map(body) ->
          body

        body when is_binary(body) and body != "" ->
          case Jason.decode(body) do
            {:ok, parsed} -> parsed
            _ -> %{"raw" => body}
          end

        _ ->
          %{}
      end

    result =
      RequestsRepo.create_request(%{
        path: request_info.path,
        ip: request_info.remote_ip,
        headers: request_info.headers,
        method: request_info.method,
        body_raw: formatted_body_raw,
        body_parsed: formatted_body_parsed,
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
