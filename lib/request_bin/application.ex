defmodule RequestBin.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Oban.Telemetry.attach_default_logger()

    children = [
      RequestBinWeb.Telemetry,
      RequestBin.Repo,
      {Oban, Application.fetch_env!(:request_bin, Oban)},
      RequestBin.RateLimit,
      {Phoenix.PubSub, name: RequestBin.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: RequestBin.Finch},
      # Start a worker by calling: RequestBin.Worker.start_link(arg)
      # {RequestBin.Worker, arg},
      # Start to serve requests, typically the last entry
      RequestBinWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: RequestBin.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    RequestBinWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
