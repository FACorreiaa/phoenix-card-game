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
       game_mode: nil,
       # :menu, :single_player, :multiplayer_lobby, :playing
       game_state: :menu,
       cards: [],
       flipped_cards: [],
       matched_cards: [],
       players: %{},
       current_player: nil,
       winner: nil,
       turns: 0,
       player_id: nil,
       chat_messages: [],
       lobby_host: nil
     )}
  end

  @impl true
  def handle_info({:send_chat_message, {player_id, message}}, socket) do
    ExCardGameWeb.Endpoint.broadcast("game:chat", "new_message", {player_id, message})
    {:noreply, socket}
  end

  @impl true
  def handle_info(%{event: "new_message", payload: {player_id, message}}, socket) do
    {:noreply, update(socket, :chat_messages, &(&1 ++ [{player_id, message}]))}
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
       game_state: game_state.game_state,
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
  def handle_info(%{event: "lobby_update", payload: lobby_state}, socket) do
    {:noreply,
     socket
     |> assign(
       players: lobby_state.players,
       lobby_host: lobby_state.lobby_host
     )}
  end

  @impl true
  def handle_event("select_single_player", _, socket) do
    player_id = "Player"

    {:noreply,
     socket
     |> assign(
       game_mode: :single_player,
       game_state: :playing,
       player_id: player_id,
       players: %{player_id => %{score: 0}},
       current_player: player_id,
       cards: Card.build_deck(),
       turns: 0,
       winner: nil
     )}
  end

  @impl true
  def handle_event("select_multiplayer", _, socket) do
    player_id = "anon" <> Integer.to_string(:rand.uniform(1_000_000))

    {:noreply,
     socket
     |> assign(
       game_mode: :multiplayer,
       game_state: :multiplayer_lobby,
       player_id: player_id,
       players: %{player_id => %{score: 0}},
       lobby_host: player_id
     )}
  end

  @impl true
  def handle_event("join_lobby", _, socket) do
    player_id = "anon" <> Integer.to_string(:rand.uniform(1_000_000))

    new_socket =
      socket
      |> assign(player_id: player_id)
      |> update(:players, &Map.put(&1, player_id, %{score: 0}))

    broadcast_lobby_state(new_socket)
    {:noreply, new_socket}
  end

  @impl true
  def handle_event("start_multiplayer_game", _, socket) do
    # Only host can start
    if socket.assigns.player_id == socket.assigns.lobby_host do
      player_ids = Map.keys(socket.assigns.players)
      first_player = Enum.at(player_ids, 0)

      new_socket =
        socket
        |> assign(
          game_state: :playing,
          cards: Card.build_deck(),
          current_player: first_player,
          turns: 0,
          winner: nil
        )

      broadcast_game_state(new_socket)
      {:noreply, new_socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("back_to_menu", _, socket) do
    {:noreply,
     socket
     |> assign(
       game_mode: nil,
       game_state: :menu,
       cards: [],
       flipped_cards: [],
       matched_cards: [],
       players: %{},
       current_player: nil,
       winner: nil,
       turns: 0,
       player_id: nil,
       chat_messages: [],
       lobby_host: nil
     )}
  end

  @impl true
  def handle_event("flip_card", %{"id" => id}, socket) do
    # In single player mode, always allow flipping
    # In multiplayer, only allow if it's your turn
    can_flip =
      socket.assigns.game_mode == :single_player ||
        socket.assigns.current_player == socket.assigns.player_id

    if can_flip do
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
          if socket.assigns.game_mode == :multiplayer do
            broadcast_game_state(new_socket)
          end

          {:noreply, new_socket}
        end
      end
    else
      {:noreply, socket}
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
    <Layouts.app flash={@flash}>
      <div class="min-h-screen bg-gradient-to-br from-purple-50 to-blue-50 dark:from-gray-900 dark:to-gray-800 -mx-4 sm:-mx-6 lg:-mx-8 -mt-20 px-4 py-8">
        <div class="max-w-7xl mx-auto">
          <%!-- Header --%>
          <div class="text-center mb-8">
            <h1 class="text-5xl font-bold bg-gradient-to-r from-purple-600 to-blue-500 bg-clip-text text-transparent mb-2">
              Memory Card Game
            </h1>
            <p class="text-gray-600 dark:text-gray-400">
              Find matching pairs {if(@game_mode == :multiplayer, do: "and compete with friends!", else: "!")}
            </p>
          </div>

          <%= case @game_state do %>
            <% :menu -> %>
              <%!-- Mode Selection Menu --%>
              <div class="text-center space-y-8 py-12">
                <div class="text-6xl mb-4">🎮</div>
                <h2 class="text-3xl font-bold text-gray-700 dark:text-gray-300">
                  Choose Game Mode
                </h2>
                <div class="grid grid-cols-1 md:grid-cols-2 gap-6 max-w-3xl mx-auto mt-8">
                  <%!-- Single Player --%>
                  <button
                    phx-click="select_single_player"
                    class="group bg-white dark:bg-gray-800 p-8 rounded-2xl shadow-lg hover:shadow-2xl transition-all hover:scale-105 border-2 border-transparent hover:border-purple-500"
                  >
                    <div class="text-5xl mb-4">🎯</div>
                    <h3 class="text-2xl font-bold text-gray-800 dark:text-gray-200 mb-2">
                      Single Player
                    </h3>
                    <p class="text-gray-600 dark:text-gray-400">
                      Play alone and try to find all pairs in the fewest turns possible!
                    </p>
                  </button>
                  <%!-- Multiplayer --%>
                  <button
                    phx-click="select_multiplayer"
                    class="group bg-white dark:bg-gray-800 p-8 rounded-2xl shadow-lg hover:shadow-2xl transition-all hover:scale-105 border-2 border-transparent hover:border-blue-500"
                  >
                    <div class="text-5xl mb-4">👥</div>
                    <h3 class="text-2xl font-bold text-gray-800 dark:text-gray-200 mb-2">
                      Multiplayer
                    </h3>
                    <p class="text-gray-600 dark:text-gray-400">
                      Create a lobby and compete with friends in turn-based gameplay!
                    </p>
                  </button>
                </div>
              </div>
            <% :multiplayer_lobby -> %>
              <%!-- Multiplayer Lobby --%>
              <div class="max-w-4xl mx-auto">
                <div class="bg-white dark:bg-gray-800 rounded-2xl shadow-lg p-8">
                  <div class="flex items-center justify-between mb-6">
                    <h2 class="text-2xl font-bold text-gray-800 dark:text-gray-200">
                      <.icon name="hero-users" class="w-6 h-6 inline mr-2" />
                      Game Lobby
                    </h2>
                    <button phx-click="back_to_menu" class="btn btn-ghost btn-sm">
                      <.icon name="hero-arrow-left" class="w-4 h-4 mr-1" />
                      Back
                    </button>
                  </div>

                  <div class="mb-6">
                    <h3 class="text-lg font-semibold text-gray-700 dark:text-gray-300 mb-4">
                      Players ({map_size(@players)})
                    </h3>
                    <div class="space-y-3">
                      <%= for {player_id, _player} <- @players do %>
                        <div class="flex items-center gap-3 px-4 py-3 bg-gray-50 dark:bg-gray-900/20 rounded-xl">
                          <div class="w-10 h-10 rounded-full bg-gradient-to-br from-purple-500 to-blue-500 flex items-center justify-center text-white font-bold">
                            {String.first(player_id)}
                          </div>
                          <div class="flex-1">
                            <div class="font-semibold text-gray-800 dark:text-gray-200">
                              {player_id}
                            </div>
                            <%= if player_id == @lobby_host do %>
                              <div class="text-xs text-purple-600 dark:text-purple-400">
                                <.icon name="hero-star" class="w-3 h-3 inline" /> Host
                              </div>
                            <% end %>
                          </div>
                          <%= if player_id == @player_id do %>
                            <span class="text-xs text-gray-500 dark:text-gray-400">(You)</span>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  </div>

                  <%= if @player_id == @lobby_host do %>
                    <div class="flex gap-4 justify-center pt-4 border-t border-gray-200 dark:border-gray-700">
                      <button
                        phx-click="start_multiplayer_game"
                        class="btn btn-primary btn-lg"
                        disabled={map_size(@players) < 1}
                      >
                        <.icon name="hero-play" class="w-5 h-5 mr-2" />
                        Start Game
                      </button>
                    </div>
                  <% else %>
                    <div class="text-center text-gray-500 dark:text-gray-400 pt-4 border-t border-gray-200 dark:border-gray-700">
                      Waiting for host to start the game...
                    </div>
                  <% end %>
                </div>
              </div>
            <% :playing -> %>
              <%= cond do %>
                <% @winner -> %>
                  <%!-- Winner Screen --%>
                  <div class="text-center space-y-6 py-12">
                    <div class="text-6xl mb-4">🎉</div>
                    <h2 class="text-4xl font-bold text-purple-600 dark:text-purple-400">
                      {@winner} wins!
                    </h2>
                    <div class="text-xl text-gray-600 dark:text-gray-400">
                      Completed in
                      <span class="font-bold text-purple-600 dark:text-purple-400">{@turns}</span>
                      turns
                    </div>
                    <div class="flex gap-4 justify-center mt-8">
                      <button phx-click="reset_game" class="btn btn-primary btn-lg">
                        <.icon name="hero-arrow-path" class="w-5 h-5 mr-2" /> Play Again
                      </button>
                      <button phx-click="back_to_menu" class="btn btn-ghost btn-lg">
                        <.icon name="hero-arrow-left" class="w-5 h-5 mr-2" /> Main Menu
                      </button>
                    </div>
                  </div>
                <% true -> %>
                  <%!-- Game Board --%>
                  <div class="space-y-6">
                    <%!-- Players & Stats --%>
                    <%= if @game_mode == :multiplayer do %>
                      <div class="bg-white dark:bg-gray-800 rounded-2xl shadow-lg p-6">
                        <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
                          <div class="md:col-span-2">
                            <h2 class="text-lg font-semibold mb-4 text-gray-700 dark:text-gray-300">
                              <.icon name="hero-users" class="w-5 h-5 inline mr-2" /> Players
                            </h2>
                            <div class="flex flex-wrap gap-3">
                              <%= for {player_id, player} <- @players do %>
                                <div class={[
                                  "px-4 py-3 rounded-xl border-2 transition-all",
                                  if(player_id == @current_player,
                                    do:
                                      "border-purple-500 bg-purple-50 dark:bg-purple-900/20 scale-105 shadow-md",
                                    else:
                                      "border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-900/20"
                                  )
                                ]}>
                                  <div class="flex items-center gap-2">
                                    <%= if player_id == @current_player do %>
                                      <div class="w-2 h-2 rounded-full bg-purple-500 animate-pulse"></div>
                                    <% end %>
                                    <div>
                                      <div class={[
                                        "font-semibold text-sm",
                                        if(player_id == @current_player,
                                          do: "text-purple-700 dark:text-purple-400",
                                          else: "text-gray-700 dark:text-gray-300"
                                        )
                                      ]}>
                                        {player_id}
                                      </div>
                                      <div class="text-xs text-gray-500 dark:text-gray-400">
                                        Score: <span class="font-bold">{player.score}</span>
                                      </div>
                                    </div>
                                  </div>
                                </div>
                              <% end %>
                            </div>
                          </div>
                          <div class="flex flex-col items-center justify-center bg-gradient-to-br from-purple-100 to-blue-100 dark:from-purple-900/30 dark:to-blue-900/30 rounded-xl p-4">
                            <div class="text-3xl font-bold text-purple-600 dark:text-purple-400">
                              {@turns}
                            </div>
                            <div class="text-sm text-gray-600 dark:text-gray-400">Turns</div>
                          </div>
                        </div>
                      </div>
                    <% else %>
                      <div class="bg-white dark:bg-gray-800 rounded-2xl shadow-lg p-6">
                        <div class="flex items-center justify-between">
                          <div class="text-2xl font-bold text-purple-600 dark:text-purple-400">
                            Score: {Map.get(@players, @player_id, %{score: 0}).score}
                          </div>
                          <div class="text-2xl font-bold text-blue-600 dark:text-blue-400">
                            Turns: {@turns}
                          </div>
                        </div>
                      </div>
                    <% end %>
                    <%!-- Game Board --%>
                    <div class="bg-white dark:bg-gray-800 rounded-2xl shadow-lg p-6">
                      <div class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6 gap-3 md:gap-4">
                        <%= for card <- @cards do %>
                          <div
                            class={[
                              "card aspect-square",
                              if(card.state in [:up, :matched], do: "flipped", else: ""),
                              if((@game_mode == :multiplayer && @current_player != @player_id) ||
                                   card.state != :down,
                                do: "cursor-not-allowed",
                                else: ""
                              )
                            ]}
                            phx-click={
                              if((@game_mode == :single_player ||
                                    @current_player == @player_id) && card.state == :down,
                                do: "flip_card"
                              )
                            }
                            phx-value-id={card.id}
                          >
                            <div class="card-inner">
                              <div class="card-front">
                                <img src="/images/cover.jpeg" alt="Card Cover" class="select-none" />
                              </div>
                              <div class="card-back">
                                <img src={"/images/#{card.image}"} alt={card.name} class="select-none" />
                              </div>
                            </div>
                          </div>
                        <% end %>
                      </div>
                    </div>
                    <%!-- Actions --%>
                    <div class="flex gap-4 justify-center">
                      <button phx-click="reset_game" class="btn btn-ghost btn-sm">
                        <.icon name="hero-arrow-path" class="w-4 h-4 mr-1" /> Reset Game
                      </button>
                      <button phx-click="back_to_menu" class="btn btn-ghost btn-sm">
                        <.icon name="hero-arrow-left" class="w-4 h-4 mr-1" /> Main Menu
                      </button>
                    </div>
                  </div>
              <% end %>
          <% end %>
        </div>

        <%!-- Chat Component (only in multiplayer lobby or playing) --%>
        <%= if @game_mode == :multiplayer && @player_id do %>
          <.live_component
            module={ExCardGameWeb.ChatLive}
            id="chat"
            player_id={@player_id}
            messages={@chat_messages}
            parent={self()}
          />
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp check_for_match(socket) do
    [card1, card2] = socket.assigns.flipped_cards
    current_player_id = socket.assigns.current_player

    new_socket = update(socket, :turns, &(&1 + 1))

    if card1.name == card2.name do
      # Match - player continues their turn
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
          # Player keeps their turn since they got a match
          new_socket
        end

      if socket.assigns.game_mode == :multiplayer do
        broadcast_game_state(new_socket)
      end

      {:noreply, new_socket}
    else
      # No match
      new_socket =
        if socket.assigns.game_mode == :multiplayer do
          # In multiplayer, switch to next player
          next_player =
            new_socket.assigns.players
            |> Map.keys()
            |> Stream.cycle()
            |> Enum.drop_while(&(&1 != current_player_id))
            |> Enum.at(1)

          assign(new_socket, :current_player, next_player)
        else
          # In single player, keep same player
          new_socket
        end

      if socket.assigns.game_mode == :multiplayer do
        broadcast_game_state(new_socket)
      end

      Process.send_after(self(), :flip_back, 1000)
      {:noreply, new_socket}
    end
  end

  defp broadcast_game_state(socket) do
    ExCardGameWeb.Endpoint.broadcast("game:lobby", "game_update", %{
      game_state: socket.assigns.game_state,
      cards: socket.assigns.cards,
      flipped_cards: socket.assigns.flipped_cards,
      matched_cards: socket.assigns.matched_cards,
      players: socket.assigns.players,
      current_player: socket.assigns.current_player,
      winner: socket.assigns.winner,
      turns: socket.assigns.turns
    })
  end

  defp broadcast_lobby_state(socket) do
    ExCardGameWeb.Endpoint.broadcast("game:lobby", "lobby_update", %{
      players: socket.assigns.players,
      lobby_host: socket.assigns.lobby_host
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
