defmodule GameSimulatorWeb.Users do
  @moduledoc """
  Local user storage backed by the configured password file.
  """

  alias GameSimulator.Configuration

  @iterations 600_000
  @salt_size 16
  @hash_size 32

  @spec add(String.t(), String.t()) :: :ok | {:error, atom()}
  def add(user, password) do
    %{users_file: users_file} = Configuration.auth!()

    with :ok <- validate(user, password),
         false <- user_exists?(users_file, user),
         :ok <- File.mkdir_p(Path.dirname(users_file)),
         :ok <- File.write(users_file, user_line(user, password) <> "\n", [:append]),
         :ok <- File.chmod(users_file, 0o600) do
      :ok
    else
      true -> {:error, :already_exists}
      {:error, _reason} -> {:error, :storage}
      :invalid -> {:error, :invalid_credentials}
    end
  end

  @spec authenticate(String.t(), String.t()) :: {:ok, String.t()} | {:error, :invalid_credentials}
  def authenticate(user, password) when is_binary(user) and is_binary(password) do
    %{users_file: users_file} = Configuration.auth!()

    case File.read(users_file) do
      {:ok, users} ->
        case Enum.find(String.split(users, "\n", trim: true), &user_line?(&1, user)) do
          nil -> {:error, :invalid_credentials}
          line -> verify_password(line, password, user)
        end

      {:error, _reason} ->
        {:error, :invalid_credentials}
    end
  end

  def authenticate(_user, _password), do: {:error, :invalid_credentials}

  def validate(user, password) do
    if valid_user?(user) and is_binary(password) and byte_size(password) >= 12 and
         not String.contains?(password, ["\n", "\r"]) do
      :ok
    else
      :invalid
    end
  end

  def valid_user?(user) when is_binary(user) do
    byte_size(user) in 1..64 and user =~ ~r/\A[a-zA-Z0-9._-]+\z/
  end

  def valid_user?(_user), do: false

  def user_exists?(users_file, user) do
    case File.read(users_file) do
      {:ok, users} -> Enum.any?(String.split(users, "\n", trim: true), &user_line?(&1, user))
      {:error, :enoent} -> false
      {:error, _reason} -> true
    end
  end

  def user_line(user, password) do
    salt = :crypto.strong_rand_bytes(@salt_size)
    hash = :crypto.pbkdf2_hmac(:sha256, password, salt, @iterations, @hash_size)

    Enum.join([user, Integer.to_string(@iterations), Base.encode64(salt), Base.encode64(hash)], ":")
  end

  def user_line?(line, user) do
    case String.split(line, ":", parts: 2) do
      [^user, _rest] -> true
      _other -> false
    end
  end

  def verify_password(line, password, user) do
    case String.split(line, ":") do
      [^user, iterations, salt, hash] ->
        with {parsed_iterations, ""} when parsed_iterations == @iterations <- Integer.parse(iterations),
             {:ok, salt} <- Base.decode64(salt),
             {:ok, expected_hash} <- Base.decode64(hash) do
          # Only accept the cost written by `add/2` to prevent a malformed file from exhausting CPU.
          actual_hash =
            :crypto.pbkdf2_hmac(:sha256, password, salt, parsed_iterations, byte_size(expected_hash))

          if Plug.Crypto.secure_compare(actual_hash, expected_hash),
            do: {:ok, user},
            else: {:error, :invalid_credentials}
        else
          _error -> {:error, :invalid_credentials}
        end

      _other ->
        {:error, :invalid_credentials}
    end
  end
end
