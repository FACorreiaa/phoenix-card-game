defmodule ExCardGameWeb.GameLive do
  use ExCardGameWeb, :live_view
  alias ExCardGame.Game.Card
  alias ExCardGame.GameResult
  alias ExCardGame.Repo

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      ExCardGameWeb.Endpoint.subscribe("game:lobby")
      ExCardGameWeb.Endpoint.subscribe("game:chat")
    end

    {:ok,
     socket
     |> assign(
       cards: [],
       flipped_cards: [],
       matched_cards: [],
       players: %{},
       current_player: nil,
       winner: nil,
       turns: 0,
       player_id: nil,
       chat_messages: []
     )}
  end

  @impl true
  def handle_info({:send_chat_message, {player_id, message}}, socket) do
    ExCardGameWeb.Endpoint.broadcast("game:chat", "new_message", {player_id, message})
    {:noreply, socket}
  end

  @impl true
  def handle_info(%{event: "new_message", payload: {player_id, message}}, socket) do
    {:noreply,
     update(socket, :chat_messages, &(&1 ++ [{player_id, message}]))}
  end

  @impl true
  def handle_info(:flip_back, socket) do
    [card1, card2] = socket.assigns.flipped_cards

    updated_cards =
      Enum.map(socket.assigns.cards, fn card ->
        if card.id == card1.id or card.id == card2.id do
          %{card | state: :down}
        else
          card
        end
      end)

    new_socket =
      socket
      |> assign(cards: updated_cards, flipped_cards: [])

    broadcast_game_state(new_socket)
    {:noreply, new_socket}
  end

  @impl true
  def handle_info(%{event: "game_update", payload: game_state}, socket) do
    {:noreply,
     socket
     |> assign(
       cards: game_state.cards,
       flipped_cards: game_state.flipped_cards,
       matched_cards: game_state.matched_cards,
       players: game_state.players,
       current_player: game_state.current_player,
       winner: game_state.winner,
       turns: game_state.turns
     )}
  end

  @impl true
  def handle_event("join_game", _, socket) do
    player_id = "anon" <> Integer.to_string(:rand.uniform(1_000_000))
    socket = assign(socket, :player_id, player_id)

    players = Map.put(socket.assigns.players, player_id, %{score: 0})

    new_socket =
      socket
      |> assign(players: players)

    if map_size(players) == 1 do
      new_socket =
        new_socket
        |> assign(current_player: player_id, cards: Card.build_deck())

      broadcast_game_state(new_socket)
      {:noreply, new_socket}
    else
      broadcast_game_state(new_socket)
      {:noreply, new_socket}
    end
  end

  @impl true
  def handle_event("flip_card", %{"id" => id}, socket) do
    if socket.assigns.current_player != socket.assigns.player_id do
      {:noreply, socket}
    else
      id = String.to_integer(id)
      cards = socket.assigns.cards
      flipped_cards = socket.assigns.flipped_cards

      clicked_card = Enum.find(cards, &(&1.id == id))

      if clicked_card.state != :down || length(flipped_cards) >= 2 do
        {:noreply, socket}
      else
        updated_cards =
          Enum.map(cards, fn card ->
            if card.id == id do
              %{card | state: :up}
            else
              card
            end
          end)

        updated_clicked_card = Enum.find(updated_cards, &(&1.id == id))
        new_flipped_cards = [updated_clicked_card | flipped_cards]

        new_socket =
          socket
          |> assign(cards: updated_cards, flipped_cards: new_flipped_cards)

        if length(new_flipped_cards) == 2 do
          check_for_match(new_socket)
        else
          broadcast_game_state(new_socket)
          {:noreply, new_socket}
        end
      end
    end
  end

  @impl true
  def handle_event("reset_game", _, socket) do
    new_socket =
      socket
      |> assign(
        cards: Card.build_deck(),
        flipped_cards: [],
        matched_cards: [],
        winner: nil,
        turns: 0
      )

    broadcast_game_state(new_socket)
    {:noreply, new_socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto">
      <h1 class="text-3xl font-bold text-center my-8">Memory Card Game</h1>

      <%= if @current_player do %>
        <div class="flex justify-between items-center mb-4">
          <div>
            <h2 class="text-xl font-bold">Players</h2>
            <ul>
              <%= for {player_id, player} <- @players do %>
                <li class={if player_id == @current_player, do: "font-bold"}>
                  {player_id}: {player.score}
                </li>
              <% end %>
            </ul>
          </div>
          <div>
            <h2 class="text-xl font-bold">Turns: {@turns}</h2>
          </div>
        </div>

        <div class="grid grid-cols-4 gap-4">
          <%= for card <- @cards do %>
            <div
              class={"card #{if card.state in [:up, :matched], do: "flipped"}"}
              phx-click={if @current_player == @player_id and card.state == :down, do: "flip_card"}
              phx-value-id={card.id}
            >
              <div class="card-inner">
                <div class="card-front">
                  <img src="/images/cover.jpeg" alt="Card Cover" />
                </div>
                <div class="card-back">
                  <img src={"/images/#{card.image}"} alt={card.name} />
                </div>
              </div>
            </div>
          <% end %>
        </div>

        <%= if @winner do %>
          <div class="text-center mt-8">
            <h2 class="text-2xl font-bold">{@winner} wins!</h2>
            <button phx-click="reset_game" class="btn btn-primary mt-4">Play Again</button>
          </div>
        <% end %>
      <% else %>
        <div class="text-center">
          <button phx-click="join_game" class="btn btn-primary">Join Game</button>
        </div>
      <% end %>

      <%= if @player_id do %>
        <.live_component module={ExCardGameWeb.ChatLive} id="chat" player_id={@player_id} messages={@chat_messages} parent={self()} />
      <% end %>
    </div>
    """
  end

  defp check_for_match(socket) do
    [card1, card2] = socket.assigns.flipped_cards
    current_player_id = socket.assigns.current_player

    new_socket = update(socket, :turns, &(&1 + 1))

    if card1.name == card2.name do
      # Match
      updated_cards =
        Enum.map(new_socket.assigns.cards, fn card ->
          if card.name == card1.name do
            %{card | state: :matched}
          else
            card
          end
        end)

      players =
        update_in(new_socket.assigns.players, [current_player_id, :score], &(&1 + 1))

      new_socket =
        new_socket
        |> assign(cards: updated_cards, flipped_cards: [], players: players)
        |> assign(matched_cards: [card1, card2 | new_socket.assigns.matched_cards])

      new_socket =
        if Enum.all?(updated_cards, &(&1.state == :matched)) do
          winner =
            Enum.max_by(players, fn {_, player} -> player.score end)
            |> elem(0)

          save_game_result(winner, new_socket.assigns.turns)
          assign(new_socket, :winner, winner)
        else
          new_socket
        end

      broadcast_game_state(new_socket)
      {:noreply, new_socket}
    else
      # No match
      next_player =
        new_socket.assigns.players
        |> Map.keys()
        |> Stream.cycle()
        |> Enum.drop_while(&(&1 != current_player_id))
        |> Enum.at(1)

      new_socket = assign(new_socket, :current_player, next_player)

      broadcast_game_state(new_socket)
      Process.send_after(self(), :flip_back, 1000)
      {:noreply, new_socket}
    end
  end

  @impl true
  def handle_info(:flip_back, socket) do
    [card1, card2] = socket.assigns.flipped_cards

    updated_cards =
      Enum.map(socket.assigns.cards, fn card ->
        if card.id == card1.id or card.id == card2.id do
          %{card | state: :down}
        else
          card
        end
      end)

    new_socket =
      socket
      |> assign(cards: updated_cards, flipped_cards: [])

    broadcast_game_state(new_socket)
    {:noreply, new_socket}
  end

  @impl true
  def handle_info(%{event: "game_update", payload: game_state}, socket) do
    {:noreply,
     socket
     |> assign(
       cards: game_state.cards,
       flipped_cards: game_state.flipped_cards,
       matched_cards: game_state.matched_cards,
       players: game_state.players,
       current_player: game_state.current_player,
       winner: game_state.winner,
       turns: game_state.turns
     )}
  end

  defp broadcast_game_state(socket) do
    ExCardGameWeb.Endpoint.broadcast("game:lobby", "game_update", %{
      cards: socket.assigns.cards,
      flipped_cards: socket.assigns.flipped_cards,
      matched_cards: socket.assigns.matched_cards,
      players: socket.assigns.players,
      current_player: socket.assigns.current_player,
      winner: socket.assigns.winner,
      turns: socket.assigns.turns
    })
  end

  defp save_game_result(winner, turns) do
    GameResult.changeset(%GameResult{}, %{
      winner: winner,
      turns: turns
    })
    |> Repo.insert()
  end
end
