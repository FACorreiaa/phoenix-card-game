defmodule ExCardGameWeb.PageController do
  use ExCardGameWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
