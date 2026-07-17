defmodule RequestBin.RequestsRepoTest do
  use RequestBin.DataCase, async: true

  alias RequestBin.Bins.Request
  alias RequestBin.RequestsRepo

  test "request_fixture/2 persists required metadata for the requested bin" do
    bin = bin_fixture()

    request =
      request_fixture(bin, %{
        method: "PUT",
        path: "/hooks/order",
        ip: "198.51.100.7"
      })

    assert request.bin_id == bin.id
    assert request.method == "PUT"
    assert request.path == "/hooks/order"
    assert request.ip == "198.51.100.7"
    assert request.headers == %{"content-type" => "application/json"}
    assert request.body_raw == ~s({"event":"test"})
    assert request.body_parsed == %{"event" => "test"}
    assert request.query_params == %{"source" => "fixture"}
  end

  test "list_requests_by_bin/1 isolates bins and returns newest first" do
    bin = bin_fixture()
    other_bin = bin_fixture()
    older = request_fixture(bin)
    newer = request_fixture(bin)
    _other_request = request_fixture(other_bin)

    Repo.update_all(
      from(request in Request, where: request.id == ^older.id),
      [set: [inserted_at: ~U[2026-01-01 12:00:00Z]]],
      []
    )

    Repo.update_all(
      from(request in Request, where: request.id == ^newer.id),
      [set: [inserted_at: ~U[2026-01-01 12:00:01Z]]],
      []
    )

    assert Enum.map(RequestsRepo.list_requests_by_bin(bin.id), & &1.id) == [newer.id, older.id]
  end
end
