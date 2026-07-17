defmodule RequestBinWeb.BinLiveTest do
  use RequestBinWeb.ConnCase

  import Phoenix.LiveViewTest

  alias RequestBin.BinsRepo

  test "index renders inside the application layout and creates a bin", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/bin")

    assert has_element?(view, "#request-bin-app")
    assert has_element?(view, "header a[href='/bin']", "Request Bin")
    assert has_element?(view, "#flash-group")

    view
    |> element("#create-bin")
    |> render_click()

    assert [bin] = BinsRepo.list_bins()
    assert_redirect(view, ~p"/bin/#{bin.id}/inspect")
  end

  test "inspector renders inside the application layout and displays copied URL flash", %{
    conn: conn
  } do
    {:ok, bin} = BinsRepo.create_bin()
    {:ok, view, _html} = live(conn, ~p"/bin/#{bin.id}/inspect")

    assert has_element?(view, "#request-bin-app")
    assert has_element?(view, "#copy-input[phx-hook='CopyOnFocus']")

    render_hook(view, "copied_url", %{})

    assert has_element?(view, "#flash-info", "Bin url copied!")
  end
end
