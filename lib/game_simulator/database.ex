defmodule GameSimulator.Database do
  @moduledoc """
  Prépare le fichier SQLite local utilisé par l'application.
  """

  @filename "game_simulator.sqlite3"

  @spec path() :: String.t()
  def path do
    %{data_directory: data_directory} = GameSimulator.Configuration.auth!()
    Path.join(data_directory, @filename)
  end

  @spec ensure!() :: :ok
  def ensure! do
    db_path = path()
    File.mkdir_p!(Path.dirname(db_path))

    case Exqlite.Sqlite3.open(db_path) do
      {:ok, conn} ->
        :ok = Exqlite.Sqlite3.execute(conn, "PRAGMA foreign_keys = ON")
        :ok = Exqlite.Sqlite3.execute(conn, users_table_sql())
        :ok = ensure_column(conn, "users", "failed_login_count", "INTEGER NOT NULL DEFAULT 0")
        :ok = ensure_column(conn, "users", "locked_until", "TEXT")
        :ok = Exqlite.Sqlite3.close(conn)

      {:error, reason} ->
        raise "cannot open sqlite database #{inspect(db_path)}: #{inspect(reason)}"
    end
  end

  def with_connection(fun) when is_function(fun, 1) do
    db_path = path()
    File.mkdir_p!(Path.dirname(db_path))

    case Exqlite.Sqlite3.open(db_path) do
      {:ok, conn} ->
        try do
          :ok = Exqlite.Sqlite3.execute(conn, "PRAGMA foreign_keys = ON")
          fun.(conn)
        after
          Exqlite.Sqlite3.close(conn)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def run(conn, sql, params \\ []) do
    case Exqlite.Sqlite3.prepare(conn, sql) do
      {:ok, statement} ->
        result =
          with :ok <- Exqlite.Sqlite3.bind(statement, params),
               :done <- Exqlite.Sqlite3.step(conn, statement) do
            :ok
          else
            {:row, _row} -> :ok
            {:error, reason} -> {:error, reason}
            reason -> {:error, reason}
          end

        _ = Exqlite.Sqlite3.release(conn, statement)
        result

      {:error, reason} ->
        {:error, reason}
    end
  end

  def query(conn, sql, params \\ []) do
    case Exqlite.Sqlite3.prepare(conn, sql) do
      {:ok, statement} ->
        result =
          with :ok <- Exqlite.Sqlite3.bind(statement, params) do
            case Exqlite.Sqlite3.multi_step(conn, statement) do
              {:done, rows} -> {:ok, rows}
              {:rows, rows} -> {:ok, rows}
              {:error, reason} -> {:error, reason}
              reason -> {:error, reason}
            end
          else
            {:error, reason} -> {:error, reason}
            reason -> {:error, reason}
          end

        _ = Exqlite.Sqlite3.release(conn, statement)
        result

      {:error, reason} ->
        {:error, reason}
    end
  end

  def users_table_sql do
    """
    CREATE TABLE IF NOT EXISTS users (
      username TEXT PRIMARY KEY,
      iterations INTEGER NOT NULL,
      salt TEXT NOT NULL,
      password_hash TEXT NOT NULL,
      permissions TEXT NOT NULL,
      failed_login_count INTEGER NOT NULL DEFAULT 0,
      locked_until TEXT,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """
  end

  def ensure_column(conn, table, column, definition) do
    case query(conn, "PRAGMA table_info(#{table})") do
      {:ok, rows} ->
        if Enum.any?(rows, fn row -> Enum.at(row, 1) == column end) do
          :ok
        else
          Exqlite.Sqlite3.execute(conn, "ALTER TABLE #{table} ADD COLUMN #{column} #{definition}")
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
