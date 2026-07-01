defmodule GameSimulator.GameSaves do
  @moduledoc """
  Sauvegardes persistantes uniques par utilisateur et type de jeu.
  """

  alias GameSimulator.Database

  @version 1

  def get(username, game_key) when is_binary(username) and is_binary(game_key) do
    Database.with_connection(fn conn ->
      case Database.query(conn, "SELECT payload, version FROM game_saves WHERE username = ? AND game_key = ?", [username, game_key]) do
        {:ok, [[payload, @version]]} -> {:ok, :erlang.binary_to_term(payload, [:safe])}
        {:ok, [[_payload, _version]]} -> {:error, :unsupported_save_version}
        {:ok, []} -> {:error, :not_found}
        {:error, reason} -> {:error, reason}
      end
    end)
  rescue
    ArgumentError -> {:error, :invalid_save}
    File.Error -> {:error, :database_unavailable}
  end

  def get(_username, _game_key), do: {:error, :not_found}

  def put(username, game_key, snapshot) when is_binary(username) and is_binary(game_key) do
    payload = :erlang.term_to_binary(snapshot)
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    Database.with_connection(fn conn ->
      Database.run(
        conn,
        """
        INSERT INTO game_saves (username, game_key, payload, version, inserted_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(username, game_key) DO UPDATE SET
          payload = excluded.payload,
          version = excluded.version,
          updated_at = excluded.updated_at
        """,
        [username, game_key, payload, @version, now, now]
      )
    end)
  rescue
    File.Error -> {:error, :database_unavailable}
  end

  def put(_username, _game_key, _snapshot), do: {:error, :invalid_save}

  def delete(username, game_key) when is_binary(username) and is_binary(game_key) do
    Database.with_connection(fn conn ->
      Database.run(conn, "DELETE FROM game_saves WHERE username = ? AND game_key = ?", [username, game_key])
    end)
  rescue
    File.Error -> {:error, :database_unavailable}
  end

  def delete(_username, _game_key), do: :ok

  def exists?(username, game_key) when is_binary(username) and is_binary(game_key) do
    case get(username, game_key) do
      {:ok, _snapshot} -> {:ok, true}
      {:error, reason} when reason in [:not_found, :invalid_save, :unsupported_save_version] -> {:ok, false}
      {:error, reason} -> {:error, reason}
    end
  end

  def exists?(_username, _game_key), do: {:ok, false}
end
