defmodule GameSimulator.BacklogFeaturesTest do
  use ExUnit.Case, async: true

  alias Belote.{Game, Table}

  test "poker history screen offers the required limits and safe text rendering" do
    html = File.read!(Path.expand("../web/index.html", File.cwd!()))
    javascript = File.read!(Path.expand("../web/assets/js/app.js", File.cwd!()))

    assert html =~ ~s(id="poker-history")
    assert html =~ ~s(value="10")
    assert html =~ ~s(value="25")
    assert html =~ ~s(value="50")
    assert javascript =~ "/api/table/extract"
    assert javascript =~ "pokerHistoryOutput.textContent"
  end

  test "completed coinche deal exposes an explanatory summary with server-calculated scores" do
    game =
      Game.new(:coinche, 1000)
      |> Map.merge(%{
        scores: %{0 => 10, 1 => 20},
        contract: %{team: 0, amount: 100, multiplier: 2, taker: 4, suit: :hearts},
        trump: :hearts,
        deal_points: %{0 => 102, 1 => 60},
        tricks: %{0 => [], 1 => []}
      })

    {:ok, game} = Game.finish_deal(game)

    state = %{
      owner: "alice",
      game_key: "belote:coinche",
      game: game,
      bot_names: Table.default_bot_names(),
      llm_mode: :local,
      llm_remaining: 10
    }

    assert %{
             taker: "Vous",
             contract: %{amount: 100, trump: "♥", multiplier: 2},
             trick_points: %{hero: 102, opponents: 60},
             contract_made: true,
             bonuses: %{dix_de_der: false, capot: false, coinche: true, surcoinche: false},
             scores: %{
               before: %{hero: 10, opponents: 20},
               after: %{hero: 414, opponents: 140}
             }
           } = Table.public_state(state, "alice").deal_summary
  end
end
