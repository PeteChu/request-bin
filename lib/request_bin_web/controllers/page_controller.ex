defmodule RequestBinWeb.PageController do
  use RequestBinWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: "/bin")
  end
end
