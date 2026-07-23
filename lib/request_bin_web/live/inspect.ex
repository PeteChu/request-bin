defmodule RequestBinWeb.BinLive.Inspect do
  @moduledoc """
  Two-pane request inspector for a bin.

  The left pane is a LiveView stream of captured requests; the right pane shows
  the selected request with tabs for Summary, Headers, Query Params, and Body.
  Body and query params are already captured and persisted by `RequestBin.Requests`
  — this LiveView only renders them.
  """

  use RequestBinWeb, :live_view

  alias RequestBin.RequestsRepo
  alias RequestBin.Utils.StringUtil

  @tabs ~w(summary headers query body)
  @max_raw_bytes 64 * 1024

  @impl true
  def mount(%{"id" => bin_id}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(RequestBin.PubSub, "bin:#{bin_id}")
    end

    hostname = URI.parse(socket.host_uri).host
    requests = RequestsRepo.list_requests_by_bin(bin_id)

    socket =
      socket
      |> stream(:requests, requests)
      |> assign(
        bin_id: bin_id,
        bin_url: "https://#{hostname}/bin/#{bin_id}",
        selected_request: List.first(requests),
        active_tab: "summary",
        body_view: "pretty",
        body_expanded: false
      )

    {:ok, socket}
  end

  @impl true
  def handle_info({:new_request, request}, socket) do
    {:noreply,
     socket
     |> stream_insert(:requests, request, at: 0)
     |> assign(selected_request: request, body_expanded: false)}
  end

  @impl true
  def handle_event("select_request", %{"id" => id}, socket) do
    selected = RequestsRepo.get_request!(id)

    {:noreply, assign(socket, selected_request: selected, body_expanded: false)}
  end

  def handle_event("set_tab", %{"tab" => tab}, socket) when tab in @tabs do
    {:noreply, assign(socket, active_tab: tab)}
  end

  def handle_event("set_body_view", %{"view" => view}, socket) when view in ~w(pretty raw) do
    {:noreply, assign(socket, body_view: view)}
  end

  def handle_event("toggle_body_expand", _params, socket) do
    {:noreply, update(socket, :body_expanded, fn expanded -> not expanded end)}
  end

  def handle_event("copied", _params, socket) do
    {:noreply, put_flash(socket, :info, "Copied!")}
  end

  def handle_event("copied_url", _params, socket) do
    {:noreply, put_flash(socket, :info, "Bin url copied!")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="w-[92vw] max-w-6xl mx-auto pb-10">
        <div class="mt-6">
          <h1 class="text-xl font-bold text-gray-800">Bin Inspector</h1>
          <input
            id="copy-input"
            class="mt-2 w-full px-4 py-2 border border-gray-300 rounded focus:outline-none focus:ring-2 focus:ring-blue-500"
            type="text"
            value={@bin_url}
            phx-hook="CopyOnFocus"
            readonly
          />
        </div>

        <div
          class="mt-6 flex border border-gray-200 rounded-lg overflow-hidden bg-white shadow-sm"
          style="min-height: 60vh"
        >
          <div
            id="requests"
            phx-update="stream"
            class="w-2/5 border-r border-gray-200 overflow-y-auto"
          >
            <p id="requests-empty" class="hidden only:block p-6 text-sm text-gray-400 text-center">
              No requests yet
            </p>
            <button
              :for={{id, request} <- @streams.requests}
              id={id}
              phx-click="select_request"
              phx-value-id={request.id}
              class={[
                "w-full flex items-center gap-3 px-4 py-3 text-left border-l-4 border-transparent hover:bg-gray-50 transition-colors",
                @selected_request && @selected_request.id == request.id &&
                  "border-blue-500 bg-blue-50"
              ]}
            >
              <span class={method_badge_class(request.method)}>{request.method}</span>
              <span class="flex-1 min-w-0 truncate text-sm font-medium text-gray-700">
                {request.path}
              </span>
              <span class="text-xs text-gray-400 whitespace-nowrap">
                {DateTime.diff(DateTime.utc_now(), request.inserted_at) |> format_time_ago}
              </span>
            </button>
          </div>

          <div class="flex-1 min-w-0 flex flex-col">
            <%= if @selected_request do %>
              <.request_detail
                request={@selected_request}
                active_tab={@active_tab}
                body_view={@body_view}
                body_expanded={@body_expanded}
              />
            <% else %>
              <.empty_detail />
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :request, :map, required: true
  attr :active_tab, :string, required: true
  attr :body_view, :string, required: true
  attr :body_expanded, :boolean, required: true

  defp request_detail(assigns) do
    ~H"""
    <div id="request-detail" class="flex flex-col h-full">
      <div class="flex items-center gap-3 px-5 py-4 border-b border-gray-200">
        <span class={method_badge_class(@request.method)}>{@request.method}</span>
        <span class="font-mono text-sm text-gray-800 truncate flex-1 min-w-0">{@request.path}</span>
        <span class="text-xs text-gray-400 whitespace-nowrap">
          {DateTime.diff(DateTime.utc_now(), @request.inserted_at) |> format_time_ago} · {@request.ip}
        </span>
      </div>

      <div id="tab-bar" class="flex gap-1 px-3 border-b border-gray-200 bg-gray-50">
        <.tab id="summary" label="Summary" active={@active_tab} />
        <.tab id="headers" label="Headers" active={@active_tab} />
        <.tab id="query" label="Query Params" active={@active_tab} />
        <.tab id="body" label="Body" active={@active_tab} />
      </div>

      <div class="flex-1 overflow-y-auto p-5">
        <%= cond do %>
          <% @active_tab == "summary" -> %>
            <.summary_tab request={@request} />
          <% @active_tab == "headers" -> %>
            <.headers_tab request={@request} />
          <% @active_tab == "query" -> %>
            <.query_tab request={@request} />
          <% @active_tab == "body" -> %>
            <.body_tab request={@request} body_view={@body_view} body_expanded={@body_expanded} />
        <% end %>
      </div>
    </div>
    """
  end

  defp empty_detail(assigns) do
    ~H"""
    <div
      id="empty-detail"
      class="flex-1 flex flex-col items-center justify-center gap-2 p-8 text-center"
    >
      <.icon name="hero-bell-alert" class="size-8 text-gray-300" />
      <p class="font-medium text-gray-600">Waiting for requests</p>
      <p class="text-sm text-gray-400">
        Send a request to your bin URL and it will appear here instantly.
      </p>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :active, :string, required: true

  defp tab(assigns) do
    ~H"""
    <button
      phx-click="set_tab"
      phx-value-tab={@id}
      class={[
        "px-3 py-2 -mb-px text-sm font-medium border-b-2 transition-colors",
        @active == @id && "border-blue-500 text-blue-600",
        @active != @id && "border-transparent text-gray-500 hover:text-gray-800"
      ]}
    >
      {@label}
    </button>
    """
  end

  attr :request, :map, required: true

  defp summary_tab(assigns) do
    ~H"""
    <div class="space-y-3 text-sm text-gray-700">
      <div class="flex gap-2">
        <span class="w-24 shrink-0 text-gray-400">Method</span>
        <span class={method_badge_class(@request.method)}>{@request.method}</span>
      </div>
      <div class="flex gap-2">
        <span class="w-24 shrink-0 text-gray-400">Path</span>
        <span class="font-mono break-all">{@request.path}</span>
      </div>
      <div class="flex gap-2">
        <span class="w-24 shrink-0 text-gray-400">From</span>
        <span>{@request.ip}</span>
      </div>
      <div class="flex gap-2">
        <span class="w-24 shrink-0 text-gray-400">Received</span>
        <span>{DateTime.diff(DateTime.utc_now(), @request.inserted_at) |> format_time_ago}</span>
      </div>
      <div class="flex gap-2">
        <span class="w-24 shrink-0 text-gray-400">Query</span>
        <span>{map_size(@request.query_params)} param(s)</span>
      </div>
      <div class="flex gap-2">
        <span class="w-24 shrink-0 text-gray-400">Body</span>
        <span>{body_summary(@request)}</span>
      </div>
    </div>
    """
  end

  attr :request, :map, required: true

  defp headers_tab(assigns) do
    ~H"""
    <div class="overflow-hidden rounded-lg border border-gray-200">
      <table class="w-full text-sm">
        <tbody class="divide-y divide-gray-100">
          <tr :for={key <- sorted_header_keys(@request.headers)}>
            <td class="px-4 py-2 w-1/3 align-top font-medium text-gray-700">
              {StringUtil.kebab_case_with_caps(key)}
            </td>
            <td class="px-4 py-2 break-all text-gray-600 font-mono">{@request.headers[key]}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :request, :map, required: true

  defp query_tab(assigns) do
    ~H"""
    <div>
      <div class="flex items-center gap-3 mb-3">
        <span class="text-xs text-gray-400">
          {map_size(@request.query_params)} param(s) · sorted
        </span>
        <div class="flex-1"></div>
        <.copy_button id="copy-query" text={query_string(@request.query_params)} />
      </div>

      <%= if map_size(@request.query_params) == 0 do %>
        <p class="text-sm text-gray-400 italic">No query parameters in this request.</p>
      <% else %>
        <div class="overflow-hidden rounded-lg border border-gray-200">
          <table class="w-full text-sm">
            <tbody class="divide-y divide-gray-100">
              <tr :for={{key, value} <- sorted_query_pairs(@request)}>
                <td class="px-4 py-2 w-2/5 align-top font-medium text-gray-700 font-mono break-all">
                  {key}
                </td>
                <td class="px-4 py-2 break-all text-gray-600 font-mono">{format_value(value)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

  attr :request, :map, required: true
  attr :body_view, :string, required: true
  attr :body_expanded, :boolean, required: true

  defp body_tab(assigns) do
    ~H"""
    <div class="flex flex-col h-full">
      <div class="flex items-center gap-2 mb-3">
        <button
          phx-click="set_body_view"
          phx-value-view="pretty"
          class={toggle_class(@body_view, "pretty")}
        >
          Pretty
        </button>
        <button
          phx-click="set_body_view"
          phx-value-view="raw"
          class={toggle_class(@body_view, "raw")}
        >
          Raw
        </button>
        <div class="flex-1"></div>
        <.copy_button id={"copy-body-#{@body_view}"} text={copy_text(@request, @body_view)} />
      </div>

      <%= cond do %>
        <% @body_view == "pretty" -> %>
          <.body_pretty request={@request} />
        <% @body_view == "raw" -> %>
          <.body_raw request={@request} expanded={@body_expanded} />
      <% end %>
    </div>
    """
  end

  attr :request, :map, required: true

  defp body_pretty(assigns) do
    ~H"""
    <%= case pretty_body(@request) do %>
      <% {:json, json} -> %>
        <pre
          id="body-pretty"
          class="bg-gray-900 rounded-lg p-4 text-sm text-emerald-300 whitespace-pre-wrap break-all font-mono overflow-auto"
        >{json}</pre>
      <% :unparseable -> %>
        <p class="text-sm text-gray-500">
          Body could not be parsed as JSON or form data. Try the
          <button phx-click="set_body_view" phx-value-view="raw" class="text-blue-600 underline">
            Raw
          </button>
          view.
        </p>
      <% :empty -> %>
        <p class="text-sm text-gray-400 italic">No parseable body in this request.</p>
    <% end %>
    """
  end

  attr :request, :map, required: true
  attr :expanded, :boolean, default: false

  defp body_raw(assigns) do
    ~H"""
    <%= case raw_body(@request, @expanded) do %>
      <% {:full, body, _size} -> %>
        <pre
          id="body-raw"
          class="bg-gray-900 rounded-lg p-4 text-sm text-gray-100 whitespace-pre-wrap break-all font-mono overflow-auto"
        >{body}</pre>
      <% {:truncated, body, size} -> %>
        <div>
          <pre
            id="body-raw"
            class="bg-gray-900 rounded-lg p-4 text-sm text-gray-100 whitespace-pre-wrap break-all font-mono overflow-auto"
          >{body}</pre>
          <div class="mt-2 flex items-center gap-3">
            <span class="text-xs text-gray-400">
              Showing first 64 KB of {kb(size)} KB
            </span>
            <button
              phx-click="toggle_body_expand"
              class="px-2.5 py-1 text-xs font-medium rounded text-blue-600 border border-blue-300 hover:bg-blue-50"
            >
              Show all
            </button>
          </div>
        </div>
      <% {:binary, size} -> %>
        <p class="text-sm text-gray-500">
          Binary body — {kb(size)} KB. Not displayable as text.
        </p>
      <% :empty -> %>
        <p class="text-sm text-gray-400 italic">No body in this request.</p>
    <% end %>
    """
  end

  attr :id, :string, required: true
  attr :text, :string, required: true

  defp copy_button(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      phx-hook="CopyOnClick"
      data-copy-text={@text}
      class="inline-flex items-center gap-1 px-2.5 py-1 text-xs font-medium text-gray-600 border border-gray-300 rounded hover:bg-gray-50 transition-colors"
    >
      <.icon name="hero-clipboard-document" class="size-3.5" /> Copy
    </button>
    """
  end

  # --- Public helpers (also referenced by templates/tests) ---

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

  # --- Private helpers ---

  defp method_badge_class(method) do
    "inline-block px-2 py-0.5 rounded text-xs font-bold text-white " <>
      case method do
        "GET" -> "bg-emerald-500"
        "POST" -> "bg-blue-500"
        "PUT" -> "bg-amber-500"
        "PATCH" -> "bg-orange-500"
        "DELETE" -> "bg-rose-500"
        _ -> "bg-gray-500"
      end
  end

  defp toggle_class(current, view) when current == view do
    "px-2.5 py-1 text-xs font-medium rounded bg-blue-600 text-white"
  end

  defp toggle_class(_current, _view) do
    "px-2.5 py-1 text-xs font-medium rounded text-gray-600 border border-gray-300 hover:bg-gray-50"
  end

  defp sorted_header_keys(headers) when is_map(headers) do
    headers |> Map.keys() |> Enum.sort()
  end

  defp sorted_query_pairs(%{query_params: query_params}) when is_map(query_params) do
    Enum.sort_by(query_params, fn {key, _value} -> to_string(key) end)
  end

  defp format_value(value) when is_list(value), do: Jason.encode!(value)
  defp format_value(value) when is_map(value), do: Jason.encode!(value)
  defp format_value(value), do: to_string(value)

  defp query_string(query_params) when is_map(query_params) do
    URI.encode_query(query_params)
  end

  defp pretty_body(%{body_parsed: body_parsed}) do
    cond do
      body_parsed == %{} -> :empty
      is_map_key(body_parsed, "_parse_error") -> :unparseable
      true -> {:json, Jason.encode!(body_parsed, pretty: true)}
    end
  end

  defp raw_body(%{body_raw: body_raw}, expanded) do
    cond do
      not is_binary(body_raw) or byte_size(body_raw) == 0 ->
        :empty

      not String.valid?(body_raw) ->
        {:binary, byte_size(body_raw)}

      true ->
        size = byte_size(body_raw)

        if size > @max_raw_bytes and not expanded do
          {:truncated, String.slice(body_raw, 0, @max_raw_bytes), size}
        else
          {:full, body_raw, size}
        end
    end
  end

  defp copy_text(request, "pretty") do
    case pretty_body(request) do
      {:json, json} -> json
      _ -> raw_string(request.body_raw)
    end
  end

  defp copy_text(request, "raw"), do: raw_string(request.body_raw)

  defp raw_string(body) when is_binary(body), do: body
  defp raw_string(_), do: ""

  defp body_summary(%{body_raw: body_raw}) when is_binary(body_raw) and byte_size(body_raw) > 0 do
    "#{byte_size(body_raw)} bytes"
  end

  defp body_summary(_), do: "empty"

  defp kb(bytes), do: Float.round(bytes / 1024, 1)
end
