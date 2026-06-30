defmodule GameSimulatorWeb.Users do
  @moduledoc """
  Local user storage backed by the SQLite `users` table.
  """

  alias GameSimulator.{Configuration, Database}

  @iterations 600_000
  @salt_size 16
  @hash_size 32
  @allowed_permissions ["admin", "poker", "llm"]
  @max_failed_logins 5
  @lock_seconds 43_200

  @spec ensure!() :: :ok
  def ensure! do
    :ok = Database.ensure!()
    import_legacy!()
  end

  @spec add(String.t(), String.t(), [String.t()]) :: :ok | {:error, atom()}
  def add(user, password, permissions \\ ["poker"]), do: create(user, password, permissions)

  def create(user, password, permissions) do
    ensure!()

    with :ok <- validate(user, password),
         {:ok, permissions} <- validate_permissions(permissions),
         false <- exists?(user),
         %{iterations: iterations, salt: salt, password_hash: password_hash} <- password_record(password),
         :ok <- insert_user(user, iterations, salt, password_hash, permissions) do
      :ok
    else
      true -> {:error, :already_exists}
      :invalid -> {:error, :invalid_credentials}
      {:error, :invalid_permissions} -> {:error, :invalid_permissions}
      {:error, _reason} -> {:error, :storage}
    end
  end

  @spec authenticate(String.t(), String.t()) :: {:ok, String.t()} | {:error, :invalid_credentials | {:locked, String.t()}}
  def authenticate(user, password) when is_binary(user) and is_binary(password) do
    ensure!()

    case get_password_record(user) do
      {:ok, record} ->
        cond do
          locked?(record) ->
            {:error, {:locked, record.locked_until}}

          verify_password_record(record, password) ->
            _ = reset_login_failures(user)
            {:ok, user}

          true ->
            register_login_failure(record)
        end

      _error ->
        {:error, :invalid_credentials}
    end
  end

  def authenticate(_user, _password), do: {:error, :invalid_credentials}

  def list do
    ensure!()

    Database.with_connection(fn conn ->
      case Database.query(conn, "SELECT username, permissions, locked_until, inserted_at, updated_at FROM users ORDER BY username") do
        {:ok, rows} -> {:ok, Enum.map(rows, &row_to_user/1)}
        {:error, _reason} -> {:error, :storage}
      end
    end)
  end

  def get(user) when is_binary(user) do
    ensure!()

    Database.with_connection(fn conn ->
      case Database.query(conn, "SELECT username, permissions, locked_until, inserted_at, updated_at FROM users WHERE username = ?", [user]) do
        {:ok, [row]} -> {:ok, row_to_user(row)}
        {:ok, []} -> {:error, :not_found}
        {:error, _reason} -> {:error, :storage}
      end
    end)
  end

  def get(_user), do: {:error, :not_found}

  def update(user, permissions) when is_binary(user) do
    ensure!()

    with {:ok, permissions} <- validate_permissions(permissions),
         {:ok, current} <- get(user),
         :ok <- protect_last_admin(current.permissions, permissions),
         :ok <- update_permissions(user, permissions) do
      :ok
    else
      {:error, :invalid_permissions} -> {:error, :invalid_permissions}
      {:error, :last_admin} -> {:error, :last_admin}
      {:error, :not_found} -> {:error, :not_found}
      {:error, _reason} -> {:error, :storage}
    end
  end

  def update(_user, _permissions), do: {:error, :not_found}

  def delete(user) when is_binary(user) do
    ensure!()

    with {:ok, current} <- get(user),
         :ok <- protect_delete_last_admin(current.permissions),
         :ok <- delete_user(user) do
      :ok
    else
      {:error, :last_admin} -> {:error, :last_admin}
      {:error, :not_found} -> {:error, :not_found}
      {:error, _reason} -> {:error, :storage}
    end
  end

  def delete(_user), do: {:error, :not_found}

  def change_password(user, current_password, new_password)
      when is_binary(user) and is_binary(current_password) and is_binary(new_password) do
    ensure!()

    with :ok <- validate_password(new_password),
         {:ok, record} <- get_password_record(user),
         true <- verify_password_record(record, current_password),
         :ok <- write_password(user, new_password) do
      :ok
    else
      :invalid -> {:error, :invalid_new_password}
      false -> {:error, :invalid_current_password}
      {:error, :not_found} -> {:error, :invalid_credentials}
      {:error, _reason} -> {:error, :storage}
    end
  end

  def change_password(_user, current_password, _new_password) when not is_binary(current_password), do: {:error, :missing_current_password}
  def change_password(_user, _current_password, new_password) when not is_binary(new_password), do: {:error, :missing_new_password}
  def change_password(_user, _current_password, _new_password), do: {:error, :invalid_credentials}

  def admin_reset_password(user, new_password) when is_binary(user) and is_binary(new_password) do
    ensure!()

    with {:ok, _current} <- get(user),
         :ok <- validate(user, new_password),
         :ok <- write_password(user, new_password) do
      :ok
    else
      :invalid -> {:error, :invalid_credentials}
      {:error, :not_found} -> {:error, :not_found}
      {:error, _reason} -> {:error, :storage}
    end
  end

  def admin_reset_password(_user, _new_password), do: {:error, :not_found}

  def validate(user, password) do
    if valid_user?(user) and validate_password(password) == :ok do
      :ok
    else
      :invalid
    end
  end

  def validate_password(password) do
    if is_binary(password) and byte_size(password) >= 12 and not String.contains?(password, ["\n", "\r"]) do
      :ok
    else
      :invalid
    end
  end

  def valid_user?(user) when is_binary(user) do
    byte_size(user) in 1..64 and user =~ ~r/\A[a-zA-Z0-9._-]+\z/
  end

  def valid_user?(_user), do: false

  def allowed_permissions, do: @allowed_permissions

  def validate_permissions(permissions) when is_list(permissions) do
    normalized =
      @allowed_permissions
      |> Enum.filter(&Enum.member?(permissions, &1))

    if length(normalized) == length(Enum.uniq(permissions)) and Enum.all?(permissions, &(&1 in @allowed_permissions)) do
      {:ok, normalized}
    else
      {:error, :invalid_permissions}
    end
  end

  def validate_permissions(_permissions), do: {:error, :invalid_permissions}

  def effective_permissions(permissions) do
    permissions = normalize_permissions(permissions)

    if "admin" in permissions do
      @allowed_permissions
    else
      permissions
    end
  end

  def has_permission?(permissions, permission) do
    permission in effective_permissions(permissions)
  end

  def public_user(account) do
    %{
      username: account.username,
      permissions: normalize_permissions(account.permissions),
      effective_permissions: effective_permissions(account.permissions),
      locked_until: Map.get(account, :locked_until),
      inserted_at: account.inserted_at,
      updated_at: account.updated_at
    }
  end

  def import_legacy! do
    %{legacy_users_file: users_file} = Configuration.auth!()

    if File.regular?(users_file) and users_count() == 0 do
      users_file
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.each(&import_legacy_line/1)
    end

    :ok
  end

  def import_legacy_line(line) do
    case String.split(line, ":") do
      [user, iterations, salt, password_hash] ->
        with true <- valid_user?(user),
             {parsed_iterations, ""} <- Integer.parse(iterations),
             {:ok, _salt} <- Base.decode64(salt),
             {:ok, _hash} <- Base.decode64(password_hash) do
          _ = insert_user(user, parsed_iterations, salt, password_hash, ["admin"])
          :ok
        else
          _error -> :ok
        end

      _other ->
        :ok
    end
  end

  def users_count do
    ensure_schema_only!()

    Database.with_connection(fn conn ->
      case Database.query(conn, "SELECT COUNT(*) FROM users") do
        {:ok, [[count]]} -> count
        _error -> 0
      end
    end)
  end

  def admin_count do
    case list() do
      {:ok, users} -> Enum.count(users, &("admin" in &1.permissions))
      {:error, _reason} -> 0
    end
  end

  def exists?(user) do
    case get(user) do
      {:ok, _user} -> true
      {:error, _reason} -> false
    end
  end

  def get_password_record(user) do
    Database.with_connection(fn conn ->
      case Database.query(conn, "SELECT username, iterations, salt, password_hash, failed_login_count, locked_until FROM users WHERE username = ?", [user]) do
        {:ok, [[username, iterations, salt, password_hash, failed_login_count, locked_until]]} ->
          {:ok, %{username: username, iterations: iterations, salt: salt, password_hash: password_hash, failed_login_count: failed_login_count, locked_until: locked_until}}

        {:ok, []} ->
          {:error, :not_found}

        {:error, _reason} ->
          {:error, :storage}
      end
    end)
  end

  def verify_password_record(%{iterations: iterations, salt: salt, password_hash: password_hash}, password) do
    with true <- iterations == @iterations,
         {:ok, decoded_salt} <- Base.decode64(salt),
         {:ok, expected_hash} <- Base.decode64(password_hash) do
      # Le coût est borné à celui de `add/3` pour empêcher une ligne DB malformée d'épuiser le CPU.
      actual_hash =
        :crypto.pbkdf2_hmac(:sha256, password, decoded_salt, iterations, byte_size(expected_hash))

      Plug.Crypto.secure_compare(actual_hash, expected_hash)
    else
      _error -> false
    end
  end

  def password_record(password) do
    salt = :crypto.strong_rand_bytes(@salt_size)
    hash = :crypto.pbkdf2_hmac(:sha256, password, salt, @iterations, @hash_size)

    %{
      iterations: @iterations,
      salt: Base.encode64(salt),
      password_hash: Base.encode64(hash)
    }
  end

  def insert_user(user, iterations, salt, password_hash, permissions) do
    now = timestamp()
    permissions_json = Poison.encode!(permissions)

    Database.with_connection(fn conn ->
      case Database.run(
             conn,
             "INSERT INTO users (username, iterations, salt, password_hash, permissions, failed_login_count, locked_until, inserted_at, updated_at) VALUES (?, ?, ?, ?, ?, 0, NULL, ?, ?)",
             [user, iterations, salt, password_hash, permissions_json, now, now]
           ) do
        :ok -> :ok
        {:error, _reason} -> {:error, :storage}
      end
    end)
  end

  def update_permissions(user, permissions) do
    now = timestamp()
    permissions_json = Poison.encode!(permissions)

    Database.with_connection(fn conn ->
      case Database.run(conn, "UPDATE users SET permissions = ?, updated_at = ? WHERE username = ?", [permissions_json, now, user]) do
        :ok -> :ok
        {:error, _reason} -> {:error, :storage}
      end
    end)
  end

  def delete_user(user) do
    Database.with_connection(fn conn ->
      case Database.run(conn, "DELETE FROM users WHERE username = ?", [user]) do
        :ok -> :ok
        {:error, _reason} -> {:error, :storage}
      end
    end)
  end

  def write_password(user, password) do
    %{iterations: iterations, salt: salt, password_hash: password_hash} = password_record(password)
    now = timestamp()

    Database.with_connection(fn conn ->
      case Database.run(
             conn,
             "UPDATE users SET iterations = ?, salt = ?, password_hash = ?, updated_at = ? WHERE username = ?",
             [iterations, salt, password_hash, now, user]
           ) do
        :ok -> :ok
        {:error, _reason} -> {:error, :storage}
      end
    end)
  end

  def unlock(user) when is_binary(user) do
    ensure!()

    with {:ok, _current} <- get(user),
         :ok <- reset_login_failures(user) do
      :ok
    else
      {:error, :not_found} -> {:error, :not_found}
      {:error, _reason} -> {:error, :storage}
    end
  end

  def unlock(_user), do: {:error, :not_found}

  def locked?(%{locked_until: nil}), do: false
  def locked?(%{locked_until: ""}), do: false

  def locked?(%{locked_until: locked_until}) when is_binary(locked_until) do
    case DateTime.from_iso8601(locked_until) do
      {:ok, until, _offset} -> DateTime.compare(until, DateTime.utc_now()) == :gt
      _error -> false
    end
  end

  def locked?(_record), do: false

  def register_login_failure(%{username: user, failed_login_count: failed_login_count}) do
    next_count = failed_login_count + 1

    if next_count >= @max_failed_logins do
      locked_until = DateTime.utc_now() |> DateTime.add(@lock_seconds, :second) |> DateTime.truncate(:second) |> DateTime.to_iso8601()

      case lock_user(user, next_count, locked_until) do
        :ok -> {:error, {:locked, locked_until}}
        {:error, _reason} -> {:error, :invalid_credentials}
      end
    else
      _ = update_failed_login_count(user, next_count)
      {:error, :invalid_credentials}
    end
  end

  def reset_login_failures(user) do
    now = timestamp()

    Database.with_connection(fn conn ->
      case Database.run(conn, "UPDATE users SET failed_login_count = 0, locked_until = NULL, updated_at = ? WHERE username = ?", [now, user]) do
        :ok -> :ok
        {:error, _reason} -> {:error, :storage}
      end
    end)
  end

  def update_failed_login_count(user, count) do
    now = timestamp()

    Database.with_connection(fn conn ->
      case Database.run(conn, "UPDATE users SET failed_login_count = ?, updated_at = ? WHERE username = ?", [count, now, user]) do
        :ok -> :ok
        {:error, _reason} -> {:error, :storage}
      end
    end)
  end

  def lock_user(user, count, locked_until) do
    now = timestamp()

    Database.with_connection(fn conn ->
      case Database.run(conn, "UPDATE users SET failed_login_count = ?, locked_until = ?, updated_at = ? WHERE username = ?", [count, locked_until, now, user]) do
        :ok -> :ok
        {:error, _reason} -> {:error, :storage}
      end
    end)
  end

  def protect_last_admin(current_permissions, new_permissions) do
    if "admin" in current_permissions and "admin" not in new_permissions and admin_count() <= 1 do
      {:error, :last_admin}
    else
      :ok
    end
  end

  def protect_delete_last_admin(current_permissions) do
    if "admin" in current_permissions and admin_count() <= 1 do
      {:error, :last_admin}
    else
      :ok
    end
  end

  def row_to_user([username, permissions_json, inserted_at, updated_at]) do
    %{
      username: username,
      permissions: decode_permissions(permissions_json),
      locked_until: nil,
      inserted_at: inserted_at,
      updated_at: updated_at
    }
  end

  def row_to_user([username, permissions_json, locked_until, inserted_at, updated_at]) do
    %{
      username: username,
      permissions: decode_permissions(permissions_json),
      locked_until: locked_until,
      inserted_at: inserted_at,
      updated_at: updated_at
    }
  end

  def decode_permissions(permissions_json) when is_binary(permissions_json) do
    case Poison.decode(permissions_json) do
      {:ok, permissions} -> normalize_permissions(permissions)
      _error -> []
    end
  end

  def decode_permissions(_permissions_json), do: []

  def normalize_permissions(permissions) when is_list(permissions) do
    @allowed_permissions
    |> Enum.filter(&Enum.member?(permissions, &1))
  end

  def normalize_permissions(_permissions), do: []

  def timestamp do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  def ensure_schema_only!, do: Database.ensure!()
end
