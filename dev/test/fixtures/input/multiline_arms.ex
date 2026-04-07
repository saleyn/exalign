defmodule Example.MultilineArms do
  def process(event) do
    case event do
      {:user, :created, user} ->
        user
        |> send_welcome_email()
        |> log_event(:created)

      {:user, :updated, user} ->
        user
        |> notify_watchers()
        |> log_event(:updated)

      {:user, :deleted, user} ->
        user
        |> revoke_sessions()
        |> archive_data()
        |> log_event(:deleted)

      {:system, action} ->
        Logger.info("System event: #{action}")
    end
  end

  def route(path, method) do
    case {path, method} do
      {"/users", "GET"} ->
        list_users()

      {"/users", "POST"} ->
        create_user()

      {"/users/" <> id, "GET"} ->
        get_user(id)

      {"/users/" <> id, "PUT"} ->
        update_user(id)

      {"/users/" <> id, "DELETE"} ->
        delete_user(id)

      _ ->
        {:error, :not_found}
    end
  end
end
