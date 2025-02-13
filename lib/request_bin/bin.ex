defmodule RequestBin.Bins do
  alias RequestBin.BinsRepo
  alias RequestBin.ObanJobs.DeleteBinJob

  def create_and_schedule_bin() do
    {:ok, bin} = BinsRepo.create_bin()

    retention_period = String.to_integer(System.get_env("RETENTION_PERIOD") || "2")

    remove_time =
      DateTime.utc_now()
      |> DateTime.add(
        retention_period * 24,
        :hour
      )

    Oban.insert!(
      Oban.Job.new(%{bin_id: bin.id},
        worker: DeleteBinJob,
        scheduled_at: remove_time,
        queue: :default
      )
    )

    {:ok, bin}
  end
end
