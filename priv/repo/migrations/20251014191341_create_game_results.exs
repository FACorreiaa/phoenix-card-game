defmodule ExCardGame.Repo.Migrations.CreateGameResults do
  use Ecto.Migration

  def change do
    create table(:game_results) do
      add :winner, :string
      add :turns, :integer

      timestamps(type: :utc_datetime)
    end
  end
end
