defmodule RequestBinWeb.PageController do
  use RequestBinWeb, :controller

  def home(conn, _params) do
    render(conn, to: "/bin")
  end
end
