defmodule RequestBin.Bins.Bin do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "bins" do
    field :retention_period, :integer, default: 7

    has_many :requests, RequestBin.Bins.Request

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(bin, attrs) do
    bin
    |> cast(attrs, [:retention_period])
    |> validate_required([])
  end
end
