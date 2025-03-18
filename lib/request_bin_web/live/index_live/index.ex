defmodule RequestBinWeb.BinLive.Index do
  use RequestBinWeb, :live_view
  import RequestBinWeb.IndexLive.RecentBin

  alias RequestBin.Bins

  def mount(_params, _session, socket) do
    {:ok, assign(socket, bins: [], show_sidebar: false)}
  end

  def render(assigns) do
    ~H"""
    <div class="flex">
      <div class={[
        "mx-auto",
        "w-full min-h-[calc(100vh-3rem)] p-6 max-w-4xl",
        "space-y-6",
        "flex flex-1 flex-col items-center"
      ]}>
        <h1 class="text-4xl font-bold text-center text-gray-800">Request Bin</h1>
        <p class="text-lg text-center text-gray-600 max-w-2xl">
          Request Bin is your go-to tool for debugging and inspecting HTTP requests. Perfect for testing webhooks,
          API integrations, and debugging client-server communications.
        </p>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-6 max-w-2xl mt-8">
          <div class="bg-white p-4 rounded-lg shadow-sm border border-gray-100">
            <h3 class="font-semibold text-gray-800 mb-2">✨ Easy to Use</h3>
            <p class="text-gray-600">
              Create a bin in one click and start capturing HTTP requests instantly
            </p>
          </div>
          <div class="bg-white p-4 rounded-lg shadow-sm border border-gray-100">
            <h3 class="font-semibold text-gray-800 mb-2">🔍 Real-time Inspection</h3>
            <p class="text-gray-600">
              View request headers, body, and query parameters in real-time
            </p>
          </div>
          <div class="bg-white p-4 rounded-lg shadow-sm border border-gray-100">
            <h3 class="font-semibold text-gray-800 mb-2">🔒 Secure</h3>
            <p class="text-gray-600">
              Each bin has a unique URL and auto-expires for your security
            </p>
          </div>
          <div class="bg-white p-4 rounded-lg shadow-sm border border-gray-100">
            <h3 class="font-semibold text-gray-800 mb-2">💡 Developer Friendly</h3>
            <p class="text-gray-600">Perfect for webhook testing and API development</p>
          </div>
        </div>

        <div class="flex flex-col items-center space-y-4 mt-8">
          <button
            class="bg-blue-500 text-white px-6 py-3 rounded-lg hover:bg-blue-600 transition text-lg font-semibold"
            phx-click="create_bin"
          >
            Create a RequestBin
          </button>
          <p class="text-sm text-gray-500">No registration required • Free to use</p>
        </div>
      </div>

      <div
        class={[
          "w-64 h-[100vh-4rem] p-6",
          "bg-white border-l border-gray-200 shadow-sm",
          "overflow-auto",
          "transition-all translate-x-full md:translate-x-0",
          if(@show_sidebar, do: "hidden md:block", else: "!hidden")
        ]}
        id="bins-list"
        phx-hook="Bins"
        phx-class-toggle="translate-x-0 hidden lg:block"
      >
        <.recent_bin bins={@bins} />
      </div>
    </div>
    """
  end

  def handle_event("create_bin", _value, socket) do
    {:ok, bin} = Bins.create_and_schedule_bin()
    expires_at = DateTime.add(bin.inserted_at, bin.retention_period, :hour)

    bin_data = %{
      id: bin.id,
      expires_at: DateTime.to_iso8601(expires_at)
    }

    socket = push_event(socket, "store_bin", %{bin: bin_data})
    {:noreply, push_navigate(socket, to: ~p"/bin/#{bin.id}/inspect")}
  end

  def handle_event("load_bins", %{"bins" => bins}, socket) do
    {:noreply, assign(socket, bins: bins, show_sidebar: length(bins) > 0)}
  end
end
