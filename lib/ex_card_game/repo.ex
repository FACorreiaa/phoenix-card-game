defmodule ExCardGame.Repo do
  use Ecto.Repo,
    otp_app: :ex_card_game,
    adapter: Ecto.Adapters.Postgres
end
