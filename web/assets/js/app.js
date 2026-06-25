// Le token ne vit que dans l'onglet courant : fermer le navigateur déconnecte l'utilisateur.
const tokenKey = "game-simulator-token";
const appShell = document.querySelector(".app-shell");
const loginScreen = document.getElementById("login-screen");
const dashboard = document.getElementById("dashboard");
const loginForm = document.getElementById("login-form");
const authStatus = document.getElementById("auth-status");
const loginSubmit = loginForm.querySelector("button");
const sessionUser = document.getElementById("session-user");
const logoutButton = document.getElementById("logout-button");
const menuToggle = document.getElementById("menu-toggle");
const newTableButton = document.getElementById("new-table-button");
const tableLobby = document.getElementById("table-lobby");
const tableScreen = document.getElementById("table-screen");
const tableStatus = document.getElementById("table-status");
const pokerTable = document.getElementById("poker-table");
const board = document.getElementById("board");
const pot = document.getElementById("pot");
const actionPanel = document.getElementById("action-panel");
const recentActions = document.getElementById("recent-actions");
const leaveTableButton = document.getElementById("leave-table-button");
const resetTableButton = document.getElementById("reset-table-button");
const extractCount = document.getElementById("extract-count");
const extractButton = document.getElementById("extract-button");
const extractPanel = document.getElementById("extract-panel");
const extractOutput = document.getElementById("extract-output");
const copyExtractButton = document.getElementById("copy-extract-button");
const handResult = document.getElementById("hand-result");
const handResultReason = document.getElementById("hand-result-reason");
const handResultWinners = document.getElementById("hand-result-winners");
let table = null;
let botTimer = null;

function showDashboard(user) {
  sessionUser.textContent = user;
  appShell.classList.add("dashboard-open");
  loginScreen.hidden = true;
  dashboard.hidden = false;
}

function showLogin() {
  sessionStorage.removeItem(tokenKey);
  appShell.classList.remove("dashboard-open");
  dashboard.hidden = true;
  loginScreen.hidden = false;
  table = null;
  clearTimeout(botTimer);
}

function money(cents) {
  return `${(cents / 100).toLocaleString("fr-FR", { minimumFractionDigits: 2 })} €`;
}

async function api(path, options = {}) {
  // Tous les appels de jeu portent le token ; le serveur reste l'autorité sur les actions.
  const response = await fetch(path, {
    ...options,
    headers: { "content-type": "application/json", authorization: `Bearer ${sessionStorage.getItem(tokenKey)}`, ...(options.headers || {}) }
  });

  if (!response.ok) throw new Error((await response.json().catch(() => ({}))).error || "request_failed");
  if (response.status === 204) return null;
  return response.json();
}

async function restoreTable() {
  try {
    renderTable(await api("/api/table"));
  } catch (error) {
    if (error.message === "table_not_found") {
      tableLobby.hidden = false;
      tableScreen.hidden = true;
      return;
    }

    tableStatus.textContent = "Impossible de récupérer la table.";
  }
}

async function restoreSession() {
  const token = sessionStorage.getItem(tokenKey);
  if (!token) return;

  try {
    const session = await api("/api/auth/me");
    showDashboard(session.user);
    restoreTable();
  } catch (_error) {
    showLogin();
  }
}

function card(value) {
  const element = document.createElement("span");
  element.className = "card";
  element.textContent = value;
  if (value.includes("♥") || value.includes("♦")) element.classList.add("red");
  return element;
}

function renderPlayers(players) {
  // Les cartes des PNJ restent la chaîne "hidden" jusqu'au règlement de la main.
  pokerTable.querySelectorAll(".seat").forEach((seat) => seat.remove());

  players.forEach((player) => {
    const seat = document.createElement("article");
    seat.className = `seat seat-${player.seat}${player.active ? " active" : ""}${player.folded ? " folded" : ""}`;
    seat.innerHTML = `<div class="seat-heading"><strong></strong><span class="position-badge"></span></div><span class="seat-stack"></span><span class="seat-status"></span><div class="hole-cards"></div>`;
    seat.querySelector("strong").textContent = player.name;
    seat.querySelector(".position-badge").textContent = player.dealer_button ? "BTN" : player.position;
    seat.querySelector(".position-badge").title = player.dealer_button ? "Bouton" : "Position";
    seat.querySelector(".seat-stack").textContent = money(player.stack);
    seat.querySelector(".seat-status").textContent = player.active ? "À jouer" : player.folded ? "Couché" : "";
    const cards = seat.querySelector(".hole-cards");

    if (player.cards === "hidden") {
      cards.innerHTML = "<span class=\"card hidden-card\">?</span><span class=\"card hidden-card\">?</span>";
    } else {
      player.cards.forEach((value) => cards.append(card(value)));
    }

    pokerTable.append(seat);
  });
}

function actionMeta(action) {
  const key = typeof action === "string" ? action : action?.action || "next";

  return {
    fold: { label: "Coucher", icon: "×", tone: "fold" },
    check: { label: "Check", icon: "✓", tone: "check" },
    call: { label: "Suivre", icon: "=", tone: "call" },
    all_in: { label: "Tapis", icon: "!", tone: "all-in" },
    bet: { label: "Miser", icon: "+", tone: "bet" },
    raise_to: { label: "Relancer", icon: "↑", tone: "raise" },
    next: { label: "Main suivante", icon: "→", tone: "next" }
  }[key] || { label: key, icon: "•", tone: "neutral" };
}

function actionButton(meta, action, disabled = false) {
  const button = document.createElement("button");
  button.className = `table-action table-action-${meta.tone}`;
  button.disabled = disabled;
  const icon = document.createElement("span");
  icon.className = "action-icon";
  icon.setAttribute("aria-hidden", "true");
  icon.textContent = meta.icon;
  const text = document.createElement("span");
  text.textContent = meta.label;
  button.append(icon, text);
  if (action !== null) button.addEventListener("click", () => submitAction(action));
  return button;
}

function renderActions() {
  // Les contrôles sont construits depuis les actions légales envoyées par le moteur.
  actionPanel.replaceChildren();

  if (table.hand_finished) {
    const button = actionButton(actionMeta({ action: "next" }), null);
    button.onclick = () => nextHand();
    actionPanel.append(button);
    return;
  }

  if (!table.hero_turn) {
    actionPanel.textContent = "Les PNJ réfléchissent…";
    return;
  }

  table.actions.forEach((action) => {
    if (typeof action === "string") {
      actionPanel.append(actionButton(actionMeta(action), { action }));
      return;
    }

    const [type, limits] = Object.entries(action)[0];
    const control = document.createElement("div");
    control.className = "bet-control";
    const input = document.createElement("input");
    input.type = "number";
    input.min = limits.min;
    input.max = limits.max;
    input.value = limits.min;
    input.className = "bet-input";
    const button = actionButton(actionMeta({ action: type }), null);
    button.onclick = () => submitAction({ action: type, amount: Number(input.value) });
    control.append(input, button);
    actionPanel.append(control);
  });
}

function renderResult() {
  // Le résultat ne s'affiche qu'une fois la main terminée, jamais pendant le coup.
  const result = table.hand_finished ? table.last_result : null;
  handResult.hidden = !result;
  if (!result) return;

  handResultReason.textContent = result.reason;
  handResultWinners.replaceChildren(...result.winners.map((winner) => {
    const item = document.createElement("article");
    item.className = "winner-result";
    const title = document.createElement("strong");
    title.textContent = winner.name;
    item.append(title);

    if (winner.hand) {
      const detail = document.createElement("span");
      detail.textContent = `${winner.hand.category} : ${winner.hand.ranks.join(" ")}`;
      item.append(detail);
    }

    if (winner.cards.length > 0) {
      const cards = document.createElement("div");
      cards.className = "result-cards";
      winner.cards.forEach((value) => cards.append(card(value)));
      item.append(cards);
    }

    return item;
  }));
}

function renderTable(nextTable) {
  table = nextTable;
  clearTimeout(botTimer);
  tableLobby.hidden = true;
  tableScreen.hidden = false;
  tableStatus.textContent = table.hand_finished ? "Main terminée." : table.hero_turn ? "C’est à vous de jouer." : "Action PNJ en cours.";
  pot.textContent = money(table.pot);
  board.replaceChildren(...table.board.map(card));
  renderPlayers(table.players);
  renderActions();
  renderResult();
  recentActions.replaceChildren(...table.recent_actions.map((item) => {
    const line = document.createElement("li");
    line.textContent = `${item.player} : ${item.action}`;
    return line;
  }));

  if (!table.hand_finished && !table.hero_turn) {
    // Une requête ne fait jouer qu'un PNJ pour rendre la séquence lisible.
    botTimer = setTimeout(() => advanceBot(), 700);
  }
}

async function submitAction(action) {
  try {
    renderTable(await api("/api/table/action", { method: "POST", body: JSON.stringify(action) }));
  } catch (_error) {
    tableStatus.textContent = "Cette action n’est plus disponible.";
  }
}

async function advanceBot() {
  try {
    renderTable(await api("/api/table/advance-bot", { method: "POST", body: "{}" }));
  } catch (_error) {
    restoreTable();
  }
}

async function nextHand() {
  try {
    renderTable(await api("/api/table/next-hand", { method: "POST", body: "{}" }));
  } catch (error) {
    tableStatus.textContent = error.message === "hero_busted" ? "Vous n’avez plus de jetons : quittez la table pour recommencer." : "Impossible de démarrer la main suivante.";
  }
}

function clearExtract() {
  extractOutput.value = "";
  extractPanel.hidden = true;
}

async function leaveTable() {
  try {
    await api("/api/table", { method: "DELETE" });
    clearTimeout(botTimer);
    table = null;
    clearExtract();
    tableScreen.hidden = true;
    tableLobby.hidden = false;
  } catch (_error) {
    tableStatus.textContent = "Impossible de quitter la table.";
  }
}

async function resetTable() {
  resetTableButton.disabled = true;

  try {
    await api("/api/table", { method: "DELETE" });
    clearExtract();
    renderTable(await api("/api/table", { method: "POST", body: "{}" }));
  } catch (_error) {
    tableStatus.textContent = "Impossible de reset la table.";
  } finally {
    resetTableButton.disabled = false;
  }
}

async function extractHands() {
  extractButton.disabled = true;

  try {
    const count = Math.min(Math.max(Number(extractCount.value || 10), 1), 50);
    extractCount.value = count;
    const extract = await api(`/api/table/extract?n=${count}`);
    extractOutput.value = extract.text;
    extractPanel.hidden = false;
  } catch (_error) {
    tableStatus.textContent = "Impossible de générer l’extract.";
  } finally {
    extractButton.disabled = false;
  }
}

async function copyExtract() {
  try {
    await navigator.clipboard.writeText(extractOutput.value);
    tableStatus.textContent = "Extract copié.";
  } catch (_error) {
    extractOutput.select();
    document.execCommand("copy");
    tableStatus.textContent = "Extract copié.";
  }
}

async function logout() {
  try {
    await api("/api/auth/logout", { method: "POST", body: "{}" });
  } catch (_error) {
    // La suppression locale du token reste nécessaire même si le serveur est indisponible.
  }

  showLogin();
}

loginForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  authStatus.textContent = "";
  loginSubmit.disabled = true;

  try {
    const response = await fetch("/api/auth/login", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(Object.fromEntries(new FormData(loginForm))) });
    if (!response.ok) throw new Error("invalid_credentials");
    const session = await response.json();
    sessionStorage.setItem(tokenKey, session.token);
    showDashboard(session.user);
    restoreTable();
  } catch (_error) {
    authStatus.textContent = "Utilisateur ou mot de passe incorrect.";
  } finally {
    loginSubmit.disabled = false;
  }
});

menuToggle.addEventListener("click", () => {
  const collapsed = dashboard.classList.toggle("menu-collapsed");
  menuToggle.setAttribute("aria-expanded", String(!collapsed));
  menuToggle.querySelector("span").textContent = collapsed ? "›" : "‹";
});

newTableButton.addEventListener("click", async () => {
  newTableButton.disabled = true;
  try {
    renderTable(await api("/api/table", { method: "POST", body: "{}" }));
  } catch (_error) {
    tableStatus.textContent = "Impossible de créer la table.";
  } finally {
    newTableButton.disabled = false;
  }
});

leaveTableButton.addEventListener("click", leaveTable);
resetTableButton.addEventListener("click", resetTable);
extractButton.addEventListener("click", extractHands);
copyExtractButton.addEventListener("click", copyExtract);
logoutButton.addEventListener("click", logout);

restoreSession();
