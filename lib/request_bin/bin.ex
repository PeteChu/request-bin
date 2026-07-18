defmodule RequestBin.Bins do
  alias Ecto.Multi
  alias RequestBin.Bins.Bin
  alias RequestBin.ObanJobs.DeleteBinJob
  alias RequestBin.Repo

  def create_and_schedule_bin do
    retention_period_days =
      Application.fetch_env!(:request_bin, :retention_period_days)

    Multi.new()
    |> Multi.insert(
      :bin,
      Bin.changeset(%Bin{}, %{retention_period: retention_period_days})
    )
    |> Oban.insert(:delete_job, fn %{bin: bin} ->
      DeleteBinJob.new(%{bin_id: bin.id},
        scheduled_at: expires_at(bin),
        queue: :default
      )
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{bin: bin, delete_job: _job}} -> {:ok, bin}
      {:error, _operation, reason, _changes} -> {:error, reason}
    end
  end

  def expires_at(%Bin{} = bin) do
    DateTime.add(bin.inserted_at, bin.retention_period * 86_400, :second)
  end
end
