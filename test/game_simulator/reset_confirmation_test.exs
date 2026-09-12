defmodule GameSimulator.ResetConfirmationTest do
  use ExUnit.Case, async: true

  test "requires an accessible confirmation before replacing or deleting an active game" do
    html = File.read!("web/index.html")
    javascript = File.read!("web/assets/js/app.js")

    assert html =~ ~s(id="game-reset-confirmation")
    assert html =~ "Annuler"
    assert html =~ "Confirmer"
    assert javascript =~ "showResetConfirmation"
    assert javascript =~ "Escape"
  end

  test "keeps the destructive network calls behind confirmation for poker, belote and Mr White" do
    javascript = File.read!("web/assets/js/app.js")

    assert javascript =~ "reset-table-button"
    assert javascript =~ "new-belote-button"
    assert javascript =~ "mr-white-restart"
    assert javascript =~ "confirmResetAction"
  end
end
