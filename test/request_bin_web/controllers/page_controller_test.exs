defmodule RequestBinWeb.PageControllerTest do
  use RequestBinWeb.ConnCase

  test "GET / redirects to the bin index", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/bin"
  end
end
