defmodule ExCardGame.Game.Card do
  defstruct [:id, :name, :image, :state]

  def build_deck do
    cards_data = [
      %{name: "hiruma", image: "hiruma.jpg"},
      %{name: "ikki", image: "ikki.jpg"},
      %{name: "ippo", image: "ippo.jpg"},
      %{name: "kongo", image: "kongo.jpg"},
      %{name: "kusanagi", image: "kusanagi.jpg"},
      %{name: "luffy", image: "luffy.jpg"},
      %{name: "reinhard", image: "reinhard.jpg"},
      %{name: "taiga", image: "taiga.jpg"},
      %{name: "takamura", image: "takamura.jpg"},
      %{name: "yoko", image: "yoko.jpg"}
    ]

    cards =
      (cards_data ++ cards_data)
      |> Enum.with_index()
      |> Enum.map(fn {card_data, index} ->
        %__MODULE__{
          id: index,
          name: card_data.name,
          image: card_data.image,
          state: :down
        }
      end)
      |> Enum.shuffle()

    cards
  end
end
