defmodule RequestBin.Repo do
  use Ecto.Repo,
    otp_app: :request_bin,
    adapter: Ecto.Adapters.Postgres
end
