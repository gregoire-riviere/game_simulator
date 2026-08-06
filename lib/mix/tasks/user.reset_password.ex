defmodule Mix.Tasks.User.ResetPassword do
  @moduledoc """
  Réinitialise le mot de passe d'un utilisateur sans l'exposer dans la commande.

      mix user.reset_password USERNAME
  """

  use Mix.Task

  @shortdoc "Réinitialise le mot de passe d'un utilisateur"

  @impl true
  def run([username]) do
    Mix.Task.run("app.config")
    {:ok, _applications} = Application.ensure_all_started(:exqlite)
    password = read_password("Nouveau mot de passe :")
    confirmation = read_password("Confirmez le mot de passe :")

    case reset(username, password, confirmation) do
      :ok -> Mix.shell().info("Mot de passe mis à jour pour #{username}.")
      {:error, :confirmation_mismatch} -> Mix.raise("les mots de passe ne correspondent pas")
      {:error, :not_found} -> Mix.raise("utilisateur introuvable : #{username}")
      {:error, :invalid_credentials} -> Mix.raise("le mot de passe doit contenir au moins 12 caractères")
      {:error, reason} -> Mix.raise("échec de la mise à jour : #{inspect(reason)}")
    end
  end

  def run(_args), do: Mix.raise("usage: mix user.reset_password USERNAME")

  def read_password(prompt) do
    Mix.shell().info(prompt)

    case :io.get_password() do
      password when is_list(password) -> List.to_string(password)
      {:error, :enotsup} -> read_visible_password()
      :eof -> Mix.raise("lecture du mot de passe interrompue")
      {:error, reason} -> Mix.raise("impossible de lire le mot de passe : #{inspect(reason)}")
    end
  end

  def read_visible_password do
    Mix.shell().error("Attention : saisie masquée indisponible, le mot de passe sera visible.")

    case IO.gets("") do
      password when is_binary(password) -> password |> String.trim_trailing("\n") |> String.trim_trailing("\r")
      :eof -> Mix.raise("lecture du mot de passe interrompue")
      {:error, reason} -> Mix.raise("impossible de lire le mot de passe : #{inspect(reason)}")
    end
  end

  def reset(username, password, password), do: GameSimulatorWeb.Users.admin_reset_password(username, password)
  def reset(_username, _password, _confirmation), do: {:error, :confirmation_mismatch}
end
