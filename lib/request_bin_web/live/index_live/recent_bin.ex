defmodule RequestBinWeb.IndexLive.RecentBin do
  use RequestBinWeb, :live_component

  def recent_bin(assigns) do
    ~H"""
    <h2 class="text-xl font-semibold mb-4">Recent bins</h2>
    <div class="space-y-2">
      <%= for bin <- @bins do %>
        <div class="block">
          <a href={~p"/bin/#{bin["id"]}/inspect"}>
            <div class="text-sm text-blue-600 underline">
              {String.slice(bin["id"], 0..7)}
            </div>
          </a>
          <div id="local-expires-at" class="text-xs text-gray-500" phx-hook="LocalTime">
            Expires: <span data-expires-at={bin["expires_at"]}></span>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
