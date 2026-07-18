defmodule RequestBinWeb.BinController do
  use RequestBinWeb, :controller

  alias RequestBin.Requests

  def collect(conn, params), do: handle_request(conn, params)

  defp handle_request(conn, params) do
    case extract_process_request(conn, params) do
      {:ok, _bin_id} ->
        send_response(conn, :ok, "ok")

      {:error, :bin_not_found} ->
        send_response(conn, :not_found, "bin not found")

      {:error, :invalid_params} ->
        send_response(conn, :bad_request, "invalid request parameters")

      {:error, :body_not_captured} ->
        send_response(conn, :unprocessable_entity, "request body was not captured")

      {:error, %Ecto.Changeset{}} ->
        send_response(conn, :unprocessable_entity, "request could not be stored")

      {:error, _error} ->
        send_response(conn, :unprocessable_entity, "request could not be processed")
    end
  end

  defp extract_process_request(conn, params) do
    with {:ok, request_info} <- Requests.extract_request_info(conn),
         {:ok, request} <- Requests.process_request(request_info, params) do
      {:ok, request.bin_id}
    end
  end

  defp send_response(conn, status, message) do
    conn
    |> put_status(status)
    |> text(message)
  end
end
