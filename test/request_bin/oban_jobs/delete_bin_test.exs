defmodule RequestBin.ObanJobs.DeleteBinJobTest do
  use RequestBin.DataCase

  alias RequestBin.Bins.Bin
  alias RequestBin.Bins.Request
  alias RequestBin.ObanJobs.DeleteBinJob

  test "deletes a bin and all of its requests and is safe to repeat" do
    bin = bin_fixture()
    request_fixture(bin)
    request_fixture(bin, %{path: "/webhooks/another"})
    job = %Oban.Job{args: %{"bin_id" => bin.id}}

    assert :ok = DeleteBinJob.perform(job)
    refute Repo.get(Bin, bin.id)
    assert Repo.all(from request in Request, where: request.bin_id == ^bin.id) == []

    assert :ok = DeleteBinJob.perform(job)
  end

  test "succeeds when the bin never existed" do
    job = %Oban.Job{args: %{"bin_id" => Ecto.UUID.generate()}}

    assert :ok = DeleteBinJob.perform(job)
  end
end
