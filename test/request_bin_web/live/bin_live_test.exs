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

  test "inspector shows the waiting state when the bin has no requests", %{conn: conn} do
    {:ok, bin} = BinsRepo.create_bin()
    {:ok, view, _html} = live(conn, ~p"/bin/#{bin.id}/inspect")

    assert has_element?(view, "#empty-detail", "Waiting for requests")
    assert has_element?(view, "#requests")
    assert has_element?(view, "#copy-input[phx-hook='CopyOnFocus']")
  end

  test "inspector lists captured requests with a tabbed detail pane", %{conn: conn} do
    {:ok, bin} = BinsRepo.create_bin()

    first =
      request_fixture(bin, %{
        method: "POST",
        path: "/webhooks/first",
        body_raw: ~s({"event":"first"}),
        body_parsed: %{"event" => "first"}
      })

    second =
      request_fixture(bin, %{
        method: "GET",
        path: "/webhooks/second",
        query_params: %{"alpha" => "1"}
      })

    {:ok, view, _html} = live(conn, ~p"/bin/#{bin.id}/inspect")

    assert has_element?(view, "#requests-#{first.id}")
    assert has_element?(view, "#requests-#{second.id}")
    # A request is selected by default and the tabbed detail pane is shown.
    assert has_element?(view, "#request-detail")
    assert has_element?(view, "#tab-bar")
    assert has_element?(view, "button[phx-value-tab='body']")
    # Summary is the default tab, so the body view is not rendered yet.
    refute has_element?(view, "#body-pretty")
  end

  test "selecting a request from the list updates the detail pane", %{conn: conn} do
    {:ok, bin} = BinsRepo.create_bin()

    first =
      request_fixture(bin, %{
        method: "GET",
        path: "/webhooks/first",
        body_raw: "",
        body_parsed: %{}
      })

    second =
      request_fixture(bin, %{
        method: "POST",
        path: "/webhooks/second",
        body_raw: ~s({"event":"second"}),
        body_parsed: %{"event" => "second"}
      })

    {:ok, view, _html} = live(conn, ~p"/bin/#{bin.id}/inspect")

    view
    |> element("#requests-#{first.id}")
    |> render_click()

    assert has_element?(view, "#request-detail", "/webhooks/first")

    view
    |> element("#requests-#{second.id}")
    |> render_click()

    assert has_element?(view, "#request-detail", "/webhooks/second")
  end

  test "query params tab renders sorted params and an empty state", %{conn: conn} do
    {:ok, bin} = BinsRepo.create_bin()

    with_params =
      request_fixture(bin, %{
        path: "/webhooks/params",
        query_params: %{"zebra" => "1", "alpha" => "2"}
      })

    without_params =
      request_fixture(bin, %{
        path: "/webhooks/no-params",
        query_params: %{}
      })

    {:ok, view, _html} = live(conn, ~p"/bin/#{bin.id}/inspect")

    # Select the request with params and open the Query tab.
    view
    |> element("#requests-#{with_params.id}")
    |> render_click()

    view
    |> element("button[phx-value-tab='query']")
    |> render_click()

    assert has_element?(view, "#copy-query")
    assert has_element?(view, "td", "alpha")
    assert has_element?(view, "td", "zebra")

    # Select the request with no query string for the empty state.
    view
    |> element("#requests-#{without_params.id}")
    |> render_click()

    assert has_element?(view, "p", "No query parameters in this request.")
  end

  test "body tab shows pretty and raw views with a copy control", %{conn: conn} do
    {:ok, bin} = BinsRepo.create_bin()

    _request =
      request_fixture(bin, %{
        method: "POST",
        path: "/webhooks/body",
        body_raw: ~s({"event":"created","id":42}),
        body_parsed: %{"event" => "created", "id" => 42}
      })

    {:ok, view, _html} = live(conn, ~p"/bin/#{bin.id}/inspect")

    view
    |> element("button[phx-value-tab='body']")
    |> render_click()

    # Pretty view is the default.
    assert has_element?(view, "#body-pretty")
    assert has_element?(view, "#copy-body-pretty")
    assert has_element?(view, "#body-pretty", "event")

    # Switch to raw.
    view
    |> element("button[phx-value-view='raw']")
    |> render_click()

    assert has_element?(view, "#body-raw")
    assert has_element?(view, "#copy-body-raw")
    assert has_element?(view, "#body-raw", "created")
  end

  test "new requests broadcast over pubsub are prepended and selected", %{conn: conn} do
    {:ok, bin} = BinsRepo.create_bin()

    {:ok, view, _html} = live(conn, ~p"/bin/#{bin.id}/inspect")
    assert has_element?(view, "#empty-detail")

    incoming =
      request_fixture(bin, %{
        method: "POST",
        path: "/webhooks/live",
        body_raw: ~s({"event":"live"}),
        body_parsed: %{"event" => "live"}
      })

    send(view.pid, {:new_request, incoming})
    render(view)

    assert has_element?(view, "#requests-#{incoming.id}")
    assert has_element?(view, "#request-detail", "/webhooks/live")
  end

  test "copy buttons flash a copied message", %{conn: conn} do
    {:ok, bin} = BinsRepo.create_bin()

    request_fixture(bin, %{
      path: "/webhooks/copy",
      query_params: %{"source" => "fixture"}
    })

    {:ok, view, _html} = live(conn, ~p"/bin/#{bin.id}/inspect")

    view
    |> element("button[phx-value-tab='query']")
    |> render_click()

    render_hook(view, "copied", %{})

    assert has_element?(view, "#flash-info", "Copied!")
  end
end
