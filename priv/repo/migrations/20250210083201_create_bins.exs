defmodule RequestBin.Repo.Migrations.CreateBins do
  use Ecto.Migration

  def change do
    create table(:bins, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # retention_period (days)
      add :retention_period, :integer,
        default: 2,
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:bins, [:id])

    create constraint(:bins, :retention_period_must_be_positive, check: "retention_period > 0")

    create constraint(:bins, :retention_period_must_be_less_than_a_year,
             check: "retention_period <= 365"
           )
  end
end
