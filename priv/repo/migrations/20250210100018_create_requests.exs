defmodule RequestBin.Repo.Migrations.CreateRequests do
  use Ecto.Migration

  def change do
    create table(:requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :bin_id, references(:bins, type: :binary_id)
      add :method, :string
      add :headers, :map
      add :body_raw, :binary
      add :body_parsed, :map
      add :query_params, :map
      add :path, :string
      add :ip, :string

      timestamps(type: :utc_datetime)
    end
  end
end
