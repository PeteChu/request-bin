defmodule RequestBinWeb.CoreComponents do
  @moduledoc """
  Provides the shared UI components used by RequestBin.

  The application uses Tailwind CSS for styling, Heroicons through `icon/1`,
  and Phoenix function components for its rendered UI.
  """
  use Phoenix.Component
  use Gettext, backend: RequestBinWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders a flash notice.
  """
  attr :id, :string, doc: "the optional id of the flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "arbitrary HTML attributes for the flash container"
  slot :inner_block, doc: "optional content used instead of a flash-map message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={[
        "fixed right-2 top-2 z-50 mr-2 w-80 rounded-lg p-3 ring-1 sm:w-96",
        @kind == :info && "bg-emerald-50 fill-cyan-900 text-emerald-800 ring-emerald-500",
        @kind == :error && "bg-rose-50 fill-rose-900 text-rose-900 shadow-md ring-rose-500"
      ]}
      {@rest}
    >
      <p :if={@title} class="flex items-center gap-1.5 text-sm font-semibold leading-6">
        <.icon :if={@kind == :info} name="hero-information-circle-mini" class="size-4" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle-mini" class="size-4" />
        {@title}
      </p>
      <p class="mt-2 text-sm leading-5">{msg}</p>
      <button type="button" class="group absolute right-1 top-1 p-2" aria-label={gettext("close")}>
        <.icon name="hero-x-mark-solid" class="size-5 opacity-40 group-hover:opacity-70" />
      </button>
    </div>
    """
  end

  @doc """
  Renders a Heroicon supplied by the Tailwind plugin in `assets/vendor/heroicons.js`.
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an Ecto changeset error.
  """
  def translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(RequestBinWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(RequestBinWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates all errors for a field from a keyword list.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
