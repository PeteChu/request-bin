defmodule RequestBin.BinsRepo do
  @moduledoc """
  The Bins context.
  Handle all business logic related to request bins.
  """

  import Ecto.Query, warn: false
  alias RequestBin.Repo
  alias RequestBin.Bins.Bin

  @doc """
  Returns the list of bins.
  """
  def list_bins do
    Repo.all(Bin)
  end

  @doc """
  Gets a single bin.

  Raises `Ecto.NoResultsError` if the Bin does not exist.
  """
  def get_bin!(id) do
    Repo.get!(Bin, id)
  end

  @doc """
  Gets a single bin.

  Returns `nil` if the Bin does not exist.
  """
  def get_bin(id), do: Repo.get(Bin, id)

  @doc """
  Creates a bin.

  ## Examples

      iex> create_bin(%{field: value})
      {:ok, %Bin{}}

      iex> create_bin(%{field: bad_value})
      {:error, %Ecto.Changeset{}}
  """
  def create_bin(attrs \\ %{}) do
    %Bin{} |> Bin.changeset(attrs) |> Repo.insert()
  end

  @doc """
  Updates a bin.
  """
  def update_bin(%Bin{} = bin, attrs) do
    bin |> Bin.changeset(attrs) |> Repo.update()
  end

  @doc """
  Deletes a bin.
  """
  def delete_bin(%Bin{} = bin) do
    Repo.delete(bin)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking bin changes.
  """
  def change_bin(%Bin{} = bin, attrs \\ %{}) do
    Bin.changeset(bin, attrs)
  end
end
