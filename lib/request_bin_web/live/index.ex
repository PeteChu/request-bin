defmodule RequestBinWeb.BinLive.Index do
  use RequestBinWeb, :live_view

  alias RequestBin.Bins

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="min-w-full flex flex-col items-center space-y-6">
      <h1 class="text-4xl font-bold text-center text-gray-800">Request Bin</h1>
      <p class="text-lg text-center text-gray-600">
        Request Bin is a tool for capturing and inspecting HTTP requests. Create a bin to get started.
      </p>
      <div class="flex flex-col items-center space-y-4">
        <button
          class="bg-blue-500 text-white p-2 rounded hover:bg-blue-600 transition"
          phx-click="create_bin"
        >
          Create a RequestBin
        </button>
      </div>
    </div>
    """
  end

  def handle_event("create_bin", _value, socket) do
    {:ok, bin} = Bins.create_and_schedule_bin()
    {:noreply, push_navigate(socket, to: ~p"/bin/#{bin.id}/inspect")}
  end
end
