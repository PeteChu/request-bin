defmodule RequestBin.BinsTest do
  use RequestBin.DataCase
  use Oban.Testing, repo: RequestBin.Repo

  alias RequestBin.Bins
  alias RequestBin.Bins.Bin
  alias RequestBin.ObanJobs.DeleteBinJob

  describe "Bin.changeset/2" do
    test "accepts the retention boundaries" do
      assert Bin.changeset(%Bin{}, %{retention_period: 1}).valid?
      assert Bin.changeset(%Bin{}, %{retention_period: 365}).valid?
    end

    test "rejects retention outside the allowed range" do
      assert "must be greater than 0" in errors_on(Bin.changeset(%Bin{}, %{retention_period: 0})).retention_period

      assert "must be less than or equal to 365" in errors_on(
               Bin.changeset(%Bin{}, %{retention_period: 366})
             ).retention_period
    end

    test "requires an integer retention" do
      assert "can't be blank" in errors_on(Bin.changeset(%Bin{}, %{retention_period: nil})).retention_period

      assert "is invalid" in errors_on(Bin.changeset(%Bin{}, %{retention_period: "two"})).retention_period
    end

    test "uses the schema default when retention is omitted" do
      changeset = Bin.changeset(%Bin{}, %{})

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :retention_period) == 2
    end
  end

  test "creates a bin with configured retention and schedules its deletion" do
    previous = Application.fetch_env!(:request_bin, :retention_period_days)
    Application.put_env(:request_bin, :retention_period_days, 7)
    on_exit(fn -> Application.put_env(:request_bin, :retention_period_days, previous) end)

    assert {:ok, bin} = Bins.create_and_schedule_bin()
    assert bin.retention_period == 7
    assert Repo.get!(Bin, bin.id).retention_period == 7

    assert_enqueued(
      worker: DeleteBinJob,
      args: %{bin_id: bin.id},
      scheduled_at: {Bins.expires_at(bin), delta: 1}
    )
  end

  test "expires_at/1 adds the persisted number of whole days" do
    bin = bin_fixture(%{retention_period: 7})

    assert DateTime.diff(Bins.expires_at(bin), bin.inserted_at, :second) == 7 * 86_400
  end
end
