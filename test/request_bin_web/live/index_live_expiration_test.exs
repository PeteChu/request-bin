defmodule RequestBinWeb.IndexLiveExpirationTest do
  use RequestBinWeb.ConnCase
  use Oban.Testing, repo: RequestBin.Repo

  import Phoenix.LiveViewTest

  alias RequestBin.Bins
  alias RequestBin.Bins.Bin
  alias RequestBin.Repo

  test "stores the configured days-based expiry and navigates to the inspector", %{conn: conn} do
    previous = Application.fetch_env!(:request_bin, :retention_period_days)
    Application.put_env(:request_bin, :retention_period_days, 7)
    on_exit(fn -> Application.put_env(:request_bin, :retention_period_days, previous) end)

    {:ok, view, _html} = live(conn, ~p"/bin")

    view
    |> element("#create-bin")
    |> render_click()

    assert [bin] = Repo.all(Bin)
    bin_id = bin.id
    expires_at = Bins.expires_at(bin)
    expires_at_iso8601 = DateTime.to_iso8601(expires_at)

    assert_push_event(view, "store_bin", %{
      bin: %{id: ^bin_id, expires_at: ^expires_at_iso8601}
    })

    assert {:ok, _parsed_expiry, 0} = DateTime.from_iso8601(expires_at_iso8601)
    assert DateTime.diff(expires_at, bin.inserted_at, :second) == 7 * 86_400
    assert_redirect(view, ~p"/bin/#{bin.id}/inspect")
  end
end
