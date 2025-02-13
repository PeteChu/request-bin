defmodule RequestBinWeb.BinLive.Index do
  use RequestBinWeb, :live_view

  def mount(%{"id" => bin_id}, _session, socket) do
    {:ok, assign(socket, bin_id: bin_id)}
  end

  def render(assigns) do
    ~H"""
    <div>
      <h1>Bin Inspector</h1>
      <p>Inspecting bin: {@bin_id}</p>
    </div>
    """
  end
end
