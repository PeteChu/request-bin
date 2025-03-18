defmodule RequestBinWeb.BinLive.Inspect do
  use RequestBinWeb, :live_view

  alias RequestBin.RequestsRepo
  alias RequestBin.Utils.StringUtil

  @impl true
  def mount(%{"id" => bin_id}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(RequestBin.PubSub, "bin:#{bin_id}")
    end

    hostname = URI.parse(socket.host_uri).host

    socket =
      socket
      |> assign(bin_url: "https://#{hostname}/bin/#{bin_id}")
      |> assign(requests: RequestsRepo.list_requests_by_bin(bin_id))
      |> assign(bin_id: bin_id)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-[80vw] max-w-4xl mx-auto flex flex-col items-center justify-center">
      <div class="w-full mt-6">
        <h1 class="text-xl font-bold mb-4 text-gray-800">Bin Inspector</h1>
        <input
          id="copy-input"
          class="w-full px-4 py-2 border border-gray-300 rounded focus:outline-none focus:ring-2 focus:ring-blue-500"
          type="text"
          value={@bin_url}
          phx-hook="CopyOnFocus"
          readonly
        />
      </div>
      <div class="mt-6 w-full">
        <h2 class="text-lg font-semibold mb-2">Requests</h2>
        <div class="space-y-2">
          <%= if @requests && @requests != [] do %>
            <%= for request <- @requests do %>
              <div class="border border-gray-300 rounded">
                <div class="flex bg-slate-200 p-4 justify-between">
                  <div>
                    <p class="text-sm text-gray-600"><strong>Method:</strong> {request.method}</p>
                    <p class="text-sm text-gray-600"><strong>Path:</strong> {request.path}</p>
                  </div>
                  <div class="font-light text-sm">
                    <p>{DateTime.diff(DateTime.utc_now(), request.inserted_at) |> format_time_ago}</p>
                    <p>From: {request.ip}</p>
                  </div>
                </div>
                <div class="bg-white p-4 grid grid-cols-2 gap-4">
                  <div class="text-sm text-gray-600">
                    <label class="text-xl font-bold">Query Params</label>
                    <ul class="mt-2">
                      <%= for key <- Map.keys(request.query_params) do %>
                        <li class="text-wrap">
                          <strong>{key}:</strong> {request.query_params[
                            key
                          ]}
                        </li>
                      <% end %>
                    </ul>
                  </div>
                  <div class="text-sm text-gray-600 break-words">
                    <label class="text-xl font-bold">Headers</label>
                    <ul class="mt-2">
                      <%= for key <- Map.keys(request.headers) do %>
                        <li class="text-wrap">
                          <strong>{StringUtil.kebab_case_with_caps(key)}:</strong> {request.headers[
                            key
                          ]}
                        </li>
                      <% end %>
                    </ul>
                  </div>
                </div>
              </div>
            <% end %>
          <% else %>
            <p class="text-sm text-gray-600">No requests available.</p>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_info({:new_request, request}, socket) do
    updated_requests = [request | socket.assigns.requests]
    {:noreply, assign(socket, :requests, updated_requests)}
  end

  @impl true
  def handle_event("copied_url", _params, socket) do
    socket =
      socket
      |> put_flash(:info, "Bin url copied!")

    {:noreply, socket}
  end

  def format_time_ago(diff) do
    minutes = div(diff, 60)
    hours = div(minutes, 60)
    days = div(hours, 24)

    cond do
      days > 0 -> "#{days} days ago"
      hours > 0 -> "#{hours} hours ago"
      minutes > 0 -> "#{minutes} minutes ago"
      true -> "#{diff} seconds ago"
    end
  end
end
