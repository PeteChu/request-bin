defmodule RequestBin.RequestsRepo do
  @moduledoc """
  The RequestsRepo context.
  Provides functions for managing and interacting with Request records in the database.
  """

  import Ecto.Query, warn: false

  alias RequestBin.Repo
  alias RequestBin.Bins.Request

  @doc """
  Returns the list of all requests.
  """
  def list_requests() do
    Repo.all(Request)
  end

  def list_requests_by_bin(bin_id) do
    from(r in Request, where: r.bin_id == ^bin_id)
    |> order_by({:desc, :inserted_at})
    |> Repo.all()
  end

  @doc """
  Gets a single request by id. Raises if the Request does not exist.
  """
  def get_request!(id), do: Repo.get!(Request, id)

  @doc """
  Gets a single request by id. Returns `nil` if the Request does not exist.
  """
  def get_request(id), do: Repo.get(Request, id)

  @doc """
  Creates a request with the given attributes.
  """
  def create_request(attrs \\ %{}) do
    result =
      %Request{}
      |> Request.changeset(attrs)
      |> Repo.insert()

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

  @doc """
  Updates a request with the given attributes.
  """
  def update_request(%Request{} = request, attrs) do
    request |> Request.changeset(attrs) |> Repo.update()
  end

  @doc """
  Deletes a Request.
  """
  def delete_request(%Request{} = request) do
    Repo.delete(request)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking request changes.
  """
  def change_request(%Request{} = request, attrs \\ %{}) do
    Request.changeset(request, attrs)
  end
end
