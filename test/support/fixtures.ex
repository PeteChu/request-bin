defmodule RequestBin.Fixtures do
  @moduledoc """
  Helpers for creating repository records in tests.
  """

  def bin_fixture(attrs \\ %{}) do
    {:ok, bin} = RequestBin.BinsRepo.create_bin(attrs)
    bin
  end

  def request_fixture(bin, attrs \\ %{}) do
    defaults = %{
      method: "POST",
      headers: %{"content-type" => "application/json"},
      body_raw: ~s({"event":"test"}),
      body_parsed: %{"event" => "test"},
      query_params: %{"source" => "fixture"},
      path: "/webhooks/test",
      ip: "192.0.2.1",
      bin_id: bin.id
    }

    {:ok, request} =
      defaults
      |> Map.merge(attrs)
      |> RequestBin.RequestsRepo.create_request()

    request
  end
end
