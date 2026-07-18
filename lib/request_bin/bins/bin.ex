defmodule RequestBin.Bins.Bin do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "bins" do
    # retention_period (days)
    field :retention_period, :integer, default: 2

    has_many :requests, RequestBin.Bins.Request

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(bin, attrs) do
    bin
    |> cast(attrs, [:retention_period])
    |> validate_required([:retention_period])
    |> validate_number(:retention_period, greater_than: 0, less_than_or_equal_to: 365)
    |> check_constraint(:retention_period, name: :retention_period_must_be_positive)
    |> check_constraint(:retention_period, name: :retention_period_must_be_less_than_a_year)
  end
end
