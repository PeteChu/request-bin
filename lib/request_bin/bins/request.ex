defmodule RequestBin.Bins.Request do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "requests" do
    field :path, :string
    field :ip, :string
    field :headers, :map
    field :method, :string
    field :body_raw, :string
    field :body_parsed, :map
    field :query_params, :map
    belongs_to :bin, RequestBin.Bins.Bin

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(request, attrs) do
    request
    |> cast(attrs, [
      :method,
      :headers,
      :body_raw,
      :body_parsed,
      :query_params,
      :path,
      :ip,
      :bin_id
    ])
    |> validate_required([:method, :body_raw, :path, :ip, :bin_id])
  end
end
