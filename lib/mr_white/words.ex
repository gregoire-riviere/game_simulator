defmodule MrWhite.Words do
  @moduledoc """
  Bibliothèque locale de paires de mots proches pour Mr. White.
  """

  @words_file Path.expand("../../priv/mr_white_words.txt", __DIR__)
  @external_resource @words_file
  @pairs @words_file
         |> File.read!()
         |> String.split("\n", trim: true)
         |> Enum.reject(&String.starts_with?(&1, "#"))
         |> Enum.map(fn line ->
           case String.split(line, "|", parts: 2) do
             [civil, spy] -> {String.trim(civil), String.trim(spy)}
             _invalid -> raise "paire de mots invalide: #{inspect(line)}"
           end
         end)
         |> Enum.uniq()

  def all, do: @pairs
  def count, do: length(@pairs)

  def random_pair do
    {first, second} = Enum.random(@pairs)
    if :rand.uniform(2) == 1, do: {first, second}, else: {second, first}
  end
end
