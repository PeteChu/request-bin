defmodule RequestBinWeb.BinController do
  use RequestBinWeb, :controller
  alias RequestBin.Requests

  def collect(conn, params), do: handle_request(conn, params)

  defp handle_request(conn, params) do
    case extract_process_request(conn, params) do
      {:ok, _bin_id} ->
        send_success_response(conn)

      {:error, :bin_not_found} ->
        send_error_response(conn, :not_found, "bin not found")

      {:error, error} ->
        send_error_response(conn, :unprocessable_entity, error)
    end
  end

  defp extract_process_request(conn, params) do
    with {:ok, request_info} <- Requests.extract_request_info(conn),
         {:ok, request} <- Requests.process_request(request_info, params) do
      {:ok, request.bin_id}
    end
  end

  defp send_success_response(conn) do
    conn
    |> put_status(:ok)
    |> html("ok")
  end

  defp send_error_response(conn, status, message) do
    conn
    |> put_status(status)
    |> html(message)
  end
end
