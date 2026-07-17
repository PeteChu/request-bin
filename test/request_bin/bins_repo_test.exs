defmodule RequestBin.BinsRepoTest do
  use RequestBin.DataCase, async: true

  alias RequestBin.BinsRepo

  test "create_bin/1 persists a bin with a UUID and default retention" do
    assert {:ok, bin} = BinsRepo.create_bin()
    bin_id = bin.id
    assert {:ok, ^bin_id} = Ecto.UUID.cast(bin_id)
    assert bin.retention_period == 2
    assert BinsRepo.get_bin(bin.id) == bin
  end

  test "get_bin/1 returns nil for a different valid UUID" do
    bin = bin_fixture()
    missing_id = Ecto.UUID.generate()

    assert BinsRepo.get_bin(bin.id) == bin
    assert BinsRepo.get_bin(missing_id) == nil
  end
end
