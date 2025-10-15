defmodule ExCardGame.GameResult do
  use Ecto.Schema
  import Ecto.Changeset

  schema "game_results" do
    field :winner, :string
    field :turns, :integer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(game_result, attrs) do
    game_result
    |> cast(attrs, [:winner, :turns])
    |> validate_required([:winner, :turns])
  end
end
