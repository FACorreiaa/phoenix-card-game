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
      <div class="messages">
        <%= for {player_id, message} <- @messages do %>
          <p><strong><%= player_id %>:</strong> <%= message %></p>
        <% end %>
      </div>
      <form phx-change="update_message" phx-submit="send_message" phx-target={@myself}>
        <input type="text" name="message" value={@new_message} />
        <button type="submit">Send</button>
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
