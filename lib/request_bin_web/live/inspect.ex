defmodule RequestBinWeb.BinLive.Inspect do
  alias RequestBin.RequestsRepo
  use RequestBinWeb, :live_view

  @impl true
  def mount(%{"id" => bin_id}, _session, socket) do
    hostname = URI.parse(socket.host_uri).host
    port = if Mix.env() == :dev, do: ":#{socket.host_uri.port}", else: ""
    bin_url = "http://#{hostname}#{port}/bin/#{bin_id}"

    if connected?(socket) do
      Phoenix.PubSub.subscribe(RequestBin.PubSub, "bin:#{bin_id}")
    end

    requests = RequestsRepo.list_requests_by_bin(bin_id)

    socket =
      socket
      |> assign(bin_url: bin_url)
      |> assign(requests: requests)
      |> assign(bin_id: bin_id)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center">
      <div class=" p-6 w-full max-w-md">
        <h1 class="text-xl font-bold mb-4 text-gray-800">Bin Inspector</h1>
        <input
          type="text"
          value={@bin_url}
          readonly
          class="w-full px-4 py-2 border border-gray-300 rounded focus:outline-none focus:ring-2 focus:ring-blue-500"
        />
      </div>
      <div class="mt-6 w-full max-w-md">
        <h2 class="text-lg font-semibold mb-2 text-gray-700">Requests</h2>
        <ul class="space-y-2">
          <%= if @requests && @requests != [] do %>
            <%= for request <- @requests do %>
              <li class="p-4 border border-gray-300 rounded bg-gray-50">
                <p class="text-sm text-gray-600"><strong>Method:</strong> {request.method}</p>
                <p class="text-sm text-gray-600"><strong>Path:</strong> {request.path}</p>
                <p class="text-sm text-gray-600">
                  <strong>Headers:</strong> {inspect(request.headers)}
                </p>
                <p class="text-sm text-gray-600">
                  <strong>Body:</strong> {inspect(request.body_parsed)}
                </p>
              </li>
            <% end %>
          <% else %>
            <p class="text-sm text-gray-600">No requests available.</p>
          <% end %>
        </ul>
      </div>
    </div>
    """
  end

  @impl true
  def handle_info({:new_request, request}, socket) do
    updated_requests = [request | socket.assigns.requests]
    {:noreply, assign(socket, :requests, updated_requests)}
  end
end
