defmodule RequestBinWeb.BinController do
  use RequestBinWeb, :controller
  alias RequestBin.Requests

  def show(conn, params), do: handle_request(conn, params)

  def create(conn, params), do: handle_request(conn, params)

  def update(conn, params), do: handle_request(conn, params)

  def delete(conn, params), do: handle_request(conn, params)

  defp handle_request(conn, params) do
    case extract_process_request(conn, params) do
      {:ok, bin_id} ->
        send_success_response(conn, bin_id)

      {:error, :bin_not_found} ->
        send_error_response(conn, :not_found, "Bin not found")

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

  defp send_success_response(conn, bin_id) do
    conn
    |> put_status(:ok)
    |> json(%{
      status: "success",
      data: %{
        bin_id: bin_id,
        message: "Request processed successfully"
      }
    })
  end

  defp send_error_response(conn, status, message) do
    conn
    |> put_status(status)
    |> json(%{
      status: "error",
      error: %{
        message: message
      }
    })
  end
end
