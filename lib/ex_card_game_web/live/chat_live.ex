defmodule ExCardGameWeb.ChatLive do
  use ExCardGameWeb, :live_component

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:messages, fn -> [] end)
     |> assign(:new_message, "")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="chat-container">
      <div class="chat-header bg-gradient-to-r from-purple-600 to-blue-500 text-white p-3 rounded-t-xl">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"
              />
            </svg>
            <span class="font-semibold text-sm">Game Chat</span>
          </div>
          <div class="w-2 h-2 bg-green-400 rounded-full animate-pulse"></div>
        </div>
      </div>

      <div class="messages" id="chat-messages" phx-hook="ScrollToBottom">
        <div class="hidden only:block text-center text-gray-400 dark:text-gray-500 text-sm py-8">
          No messages yet. Say hello! 👋
        </div>
        <%= for {player_id, message} <- @messages do %>
          <div class={[
            "message-item p-2 rounded-lg mb-2 transition-all",
            if(player_id == @player_id,
              do: "bg-purple-100 dark:bg-purple-900/30 ml-4",
              else: "bg-gray-100 dark:bg-gray-800/50 mr-4"
            )
          ]}>
            <div class={[
              "text-xs font-semibold mb-1",
              if(player_id == @player_id,
                do: "text-purple-700 dark:text-purple-400",
                else: "text-gray-600 dark:text-gray-400"
              )
            ]}>
              {player_id}
            </div>
            <div class="text-sm text-gray-800 dark:text-gray-200 break-words">
              {message}
            </div>
          </div>
        <% end %>
      </div>

      <form phx-change="update_message" phx-submit="send_message" phx-target={@myself}>
        <input
          type="text"
          name="message"
          value={@new_message}
          placeholder="Type a message..."
          autocomplete="off"
          maxlength="200"
        />
        <button type="submit" disabled={@new_message == ""} class={@new_message == "" && "opacity-50"}>
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8"
            />
          </svg>
        </button>
      </form>
    </div>
    """
  end

  @impl true
  def handle_event("update_message", %{"message" => message}, socket) do
    {:noreply, assign(socket, :new_message, message)}
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    send(socket.assigns.parent, {:send_chat_message, {socket.assigns.player_id, message}})
    {:noreply, assign(socket, :new_message, "")}
  end
end
