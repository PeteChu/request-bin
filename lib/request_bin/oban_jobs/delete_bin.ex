defmodule RequestBin.ObanJobs.DeleteBinJob do
  alias RequestBin.Bins.Bin
  use Oban.Worker, queue: :default, max_attempts: 20

  alias RequestBin.Repo
  alias RequestBin.Requests

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{"bin_id" => bin_id} = args

    Repo.transaction(fn ->
      Requests.delete_for_bin(bin_id)

      case Repo.get(Bin, bin_id) do
        nil -> :ok
        bin -> Repo.delete!(bin)
      end
    end)
    |> case do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
