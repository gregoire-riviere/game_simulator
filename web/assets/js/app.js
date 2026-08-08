// Le token ne vit que dans l'onglet courant : fermer le navigateur déconnecte l'utilisateur.
const tokenKey = "game-simulator-token";
const permissionNames = ["admin", "poker", "belote", "mr_white", "llm"];
const appShell = document.querySelector(".app-shell");
const loginScreen = document.getElementById("login-screen");
const dashboard = document.getElementById("dashboard");
const loginForm = document.getElementById("login-form");
const authStatus = document.getElementById("auth-status");
const loginSubmit = loginForm.querySelector("button");
const sessionUser = document.getElementById("session-user");
const logoutButton = document.getElementById("logout-button");
const menuToggle = document.getElementById("menu-toggle");
const pokerNav = document.getElementById("poker-nav");
const beloteNav = document.getElementById("belote-nav");
const mrWhiteNav = document.getElementById("mr-white-nav");
const adminNav = document.getElementById("admin-nav");
const adminNavLabel = document.getElementById("admin-nav-label");
const accountNav = document.getElementById("account-nav");
const pokerPage = document.getElementById("poker-page");
const belotePage = document.getElementById("belote-page");
const mrWhitePage = document.getElementById("mr-white-page");
const adminPage = document.getElementById("admin-page");
const accountPage = document.getElementById("account-page");
const passwordForm = document.getElementById("password-form");
const passwordStatus = document.getElementById("password-status");
const userCreateForm = document.getElementById("user-create-form");
const adminStatus = document.getElementById("admin-status");
const usersTableBody = document.getElementById("users-table-body");
const newTableButton = document.getElementById("new-table-button");
const resumeTableButton = document.getElementById("resume-table-button");
const gameTypeSelect = document.getElementById("game-type-select");
const tableLobby = document.getElementById("table-lobby");
const tableScreen = document.getElementById("table-screen");
const tableStatus = document.getElementById("table-status");
const pokerTable = document.getElementById("poker-table");
const board = document.getElementById("board");
const handNumber = document.getElementById("hand-number");
const pot = document.getElementById("pot");
const actionPanel = document.getElementById("action-panel");
const recentActions = document.getElementById("recent-actions");
const leaveTableButton = document.getElementById("leave-table-button");
const resetTableButton = document.getElementById("reset-table-button");
const llmControls = document.getElementById("llm-controls");
const llmModeSelect = document.getElementById("llm-mode-select");
const llmCredit = document.getElementById("llm-credit");
const extractCount = document.getElementById("extract-count");
const extractButton = document.getElementById("extract-button");
const extractPanel = document.getElementById("extract-panel");
const extractOutput = document.getElementById("extract-output");
const copyExtractButton = document.getElementById("copy-extract-button");
const closeExtractButton = document.getElementById("close-extract-button");
const coachingButton = document.getElementById("coaching-button");
const coachingDialog = document.getElementById("coaching-dialog");
const coachingAdvice = document.getElementById("coaching-advice");
const coachingWhy = document.getElementById("coaching-why");
const handResult = document.getElementById("hand-result");
const handResultReason = document.getElementById("hand-result-reason");
const handResultWinners = document.getElementById("hand-result-winners");
const beloteLobby = document.getElementById("belote-lobby");
const beloteScreen = document.getElementById("belote-screen");
const beloteTypeSelect = document.getElementById("belote-type-select");
const beloteTargetSelect = document.getElementById("belote-target-select");
const newBeloteButton = document.getElementById("new-belote-button");
const resumeBeloteButton = document.getElementById("resume-belote-button");
const leaveBeloteButton = document.getElementById("leave-belote-button");
const beloteLlmMode = document.getElementById("belote-llm-mode");
const beloteStatus = document.getElementById("belote-status");
const beloteScore = document.getElementById("belote-score");
const beloteContract = document.getElementById("belote-contract");
const belotePlayers = document.getElementById("belote-players");
const beloteTrick = document.getElementById("belote-trick");
const beloteHand = document.getElementById("belote-hand");
const beloteActions = document.getElementById("belote-actions");
const beloteHistory = document.getElementById("belote-history");
const mrWhiteLobby = document.getElementById("mr-white-lobby");
const mrWhiteGame = document.getElementById("mr-white-game");
const mrWhiteForm = document.getElementById("mr-white-form");
const mrWhitePlayerCount = document.getElementById("mr-white-player-count");
const mrWhiteSpyCount = document.getElementById("mr-white-spy-count");
const mrWhitePlayerFields = document.getElementById("mr-white-player-fields");
const mrWhiteStatus = document.getElementById("mr-white-status");
const mrWhiteRound = document.getElementById("mr-white-round");
const mrWhiteStage = document.getElementById("mr-white-stage");
const mrWhiteRestart = document.getElementById("mr-white-restart");
const mrWhiteChangePlayers = document.getElementById("mr-white-change-players");
let session = null;
let table = null;
let beloteTable = null;
let beloteBidAmount = null;
let botTimer = null;
let trickClearTimer = null;
let tableRetryTimer = null;
let tableRetrySeconds = 0;
let actionPending = false;
let mrWhiteState = null;
let previousScrollY = window.scrollY;

function hasPermission(permission) {
  return session && Array.isArray(session.permissions) && session.permissions.includes(permission);
}

function normalizeSession(nextSession) {
  return {
    user: nextSession.user,
    permissions: Array.isArray(nextSession.permissions) ? nextSession.permissions : []
  };
}

function showDashboard(nextSession) {
  session = normalizeSession(nextSession);
  sessionUser.textContent = session.user;
  appShell.classList.add("dashboard-open");
  loginScreen.hidden = true;
  dashboard.hidden = false;
  renderAccess();
}

function showLogin(message = "") {
  sessionStorage.removeItem(tokenKey);
  appShell.classList.remove("dashboard-open");
  dashboard.hidden = true;
  loginScreen.hidden = false;
  authStatus.textContent = message;
  session = null;
  table = null;
  mrWhiteState = null;
  actionPending = false;
  clearTimeout(botTimer);
  clearTableRetry();
}

function clearTableRetry() {
  clearInterval(tableRetryTimer);
  tableRetryTimer = null;
}

function scheduleTableRetry() {
  clearTableRetry();
  tableRetrySeconds = 5;
  tableStatus.textContent = `Connexion perdue. Nouvelle tentative dans ${tableRetrySeconds} s.`;

  tableRetryTimer = setInterval(() => {
    tableRetrySeconds -= 1;

    if (tableRetrySeconds <= 0) {
      clearTableRetry();
      restoreTable();
      return;
    }

    tableStatus.textContent = `Connexion perdue. Nouvelle tentative dans ${tableRetrySeconds} s.`;
  }, 1000);
}

function defaultView() {
  if (hasPermission("poker")) return "poker";
  if (hasPermission("belote")) return "belote";
  if (hasPermission("mr_white")) return "mr-white";
  if (hasPermission("admin")) return "admin";
  return "account";
}

function renderAccess() {
  pokerNav.hidden = !hasPermission("poker");
  beloteNav.hidden = !hasPermission("belote");
  mrWhiteNav.hidden = !hasPermission("mr_white");
  adminNav.hidden = !hasPermission("admin");
  adminNavLabel.hidden = !hasPermission("admin");
  llmControls.hidden = !hasPermission("llm");
  showView(defaultView());
}

function showView(view) {
  const allowedView = view === "admin" && !hasPermission("admin") ? defaultView() : view === "poker" && !hasPermission("poker") ? defaultView() : view === "belote" && !hasPermission("belote") ? defaultView() : view === "mr-white" && !hasPermission("mr_white") ? defaultView() : view;
  const pages = { poker: pokerPage, belote: belotePage, "mr-white": mrWhitePage, admin: adminPage, account: accountPage };
  const navs = { poker: pokerNav, belote: beloteNav, "mr-white": mrWhiteNav, admin: adminNav, account: accountNav };

  Object.entries(pages).forEach(([name, page]) => page.hidden = name !== allowedView);
  Object.entries(navs).forEach(([name, nav]) => {
    nav.classList.toggle("active", name === allowedView);
    if (name === allowedView) nav.setAttribute("aria-current", "page");
    else nav.removeAttribute("aria-current");
  });

  if (allowedView === "admin") loadAdminUsers();
  if (allowedView === "poker") restoreTable();
  if (allowedView === "belote") restoreBelote();
  if (allowedView === "mr-white") restoreMrWhite();
}

function money(cents) {
  return `${(cents / 100).toLocaleString("fr-FR", { minimumFractionDigits: 2 })} €`;
}

async function api(path, options = {}) {
  // Tous les appels applicatifs portent le token ; le serveur reste l'autorité sur les droits.
  const response = await fetch(path, {
    ...options,
    headers: { "content-type": "application/json", authorization: `Bearer ${sessionStorage.getItem(tokenKey)}`, ...(options.headers || {}) }
  });

  if (response.status === 401) {
    showLogin("Votre session a expiré, reconnectez-vous pour continuer.");
    throw new Error("session_expired");
  }

  if (!response.ok) throw new Error((await response.json().catch(() => ({}))).error || "request_failed");
  if (response.status === 204) return null;
  return response.json();
}

async function restoreTable() {
  if (!hasPermission("poker")) return;

  try {
    renderTable(await api("/api/table"));
  } catch (error) {
    if (error.message === "table_not_found") {
      clearTableRetry();
      tableLobby.hidden = false;
      tableScreen.hidden = true;
      refreshSaveStatus();
      return;
    }

    if (error.message !== "session_expired") scheduleTableRetry();
  }
}

async function refreshSaveStatus() {
  if (!hasPermission("poker")) return;

  try {
    const status = await api(`/api/table/save?game_key=${encodeURIComponent(gameTypeSelect.value)}`);
    resumeTableButton.hidden = !status.has_save;
  } catch (_error) {
    resumeTableButton.hidden = true;
  }
}

async function restoreBelote() {
  if (!hasPermission("belote")) return;

  try {
    renderBelote(await api(`/api/belote?game_key=${encodeURIComponent(beloteTypeSelect.value)}`));
  } catch (error) {
    if (error.message === "table_not_found") {
      beloteLobby.hidden = false;
      beloteScreen.hidden = true;
      refreshBeloteSaveStatus();
    }
  }
}

async function refreshBeloteSaveStatus() {
  if (!hasPermission("belote")) return;

  try {
    const status = await api(`/api/belote/save?game_key=${encodeURIComponent(beloteTypeSelect.value)}`);
    resumeBeloteButton.hidden = !status.has_save;
  } catch (_error) {
    resumeBeloteButton.hidden = true;
  }
}

function beloteActionLabel(action) {
  if (action.type === "pass") return "Passer";
  if (action.type === "coinche") return "Coincher";
  if (action.type === "surcoinche") return "Surcoincher";
  if (action.type === "take") return `Prendre ${suitLabel(action.suit)}`;
  if (action.type === "bid") return `${action.amount} ${suitLabel(action.suit)}`;
  return action.card;
}

function suitLabel(suit) {
  return { clubs: "♣", diamonds: "♦", hearts: "♥", spades: "♠" }[suit] || suit;
}

function beloteCard(value) {
  const element = document.createElement("span");
  const match = value.match(/^(10|[7-9VDRA])([♣♦♥♠])$/);
  const rank = match ? match[1] : value;
  const suit = match ? match[2] : "";
  element.className = "card belote-face-card";
  if (["V", "D", "R"].includes(rank)) element.dataset.figure = rank;
  if (suit === "♥" || suit === "♦") element.classList.add("red");
  element.setAttribute("aria-label", value);
  const top = document.createElement("small");
  const center = document.createElement("strong");
  const bottom = document.createElement("small");
  top.textContent = `${rank}${suit}`;
  center.textContent = suit;
  center.dataset.suit = suit;
  bottom.textContent = `${rank}${suit}`;
  element.append(top, center, bottom);
  return element;
}

function beloteChoice(label, active, click) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = `belote-choice${active ? " selected" : ""}`;
  button.textContent = label;
  button.onclick = click;
  return button;
}

function renderBeloteActions() {
  beloteActions.replaceChildren();

  if (beloteTable.phase === "deal_finished") {
    const button = beloteChoice("Donne suivante", true, nextBeloteDeal);
    button.classList.add("belote-next-deal");
    beloteActions.append(button);
    return;
  }

  if (!beloteTable.hero_turn) return;

  const actions = beloteTable.actions;
  const bids = actions.filter((action) => action.type === "bid");
  const takes = actions.filter((action) => action.type === "take");
  const pass = actions.find((action) => action.type === "pass");

  if (bids.length > 0) {
    const amounts = [...new Set(bids.map((action) => action.amount))];
    const panel = document.createElement("div");
    panel.className = "belote-bid-panel";
    const amountLabel = document.createElement("span");
    amountLabel.textContent = "Enchère";
    const amountChoices = document.createElement("div");
    amountChoices.className = "belote-choice-row";
    amounts.forEach((amount) => amountChoices.append(beloteChoice(amount, beloteBidAmount === amount, () => {
      beloteBidAmount = amount;
      renderBelote(beloteTable);
    })));
    panel.append(amountLabel, amountChoices);

    if (beloteBidAmount) {
      const suitChoices = document.createElement("div");
      suitChoices.className = "belote-choice-row";
      bids.filter((action) => action.amount === beloteBidAmount).forEach((action) => suitChoices.append(beloteChoice(suitLabel(action.suit), false, () => submitBeloteAction(action))));
      panel.append(suitChoices);
    }

    beloteActions.append(panel);
  } else if (takes.length > 0) {
    const panel = document.createElement("div");
    panel.className = "belote-bid-panel";
    const label = document.createElement("span");
    label.textContent = "Choisir l’atout";
    const suits = document.createElement("div");
    suits.className = "belote-choice-row";
    takes.forEach((action) => suits.append(beloteChoice(suitLabel(action.suit), false, () => submitBeloteAction(action))));
    panel.append(label, suits);
    beloteActions.append(panel);
  }

  if (pass) beloteActions.append(beloteChoice("Passer", false, () => submitBeloteAction(pass)));
  actions.filter((action) => ["coinche", "surcoinche"].includes(action.type)).forEach((action) => beloteActions.append(beloteChoice(beloteActionLabel(action), true, () => submitBeloteAction(action))));
}

function renderBelote(nextTable) {
  beloteTable = nextTable;
  if (!beloteTable.actions.some((action) => action.type === "bid")) beloteBidAmount = null;
  clearTimeout(botTimer);
  clearTimeout(trickClearTimer);
  beloteLobby.hidden = true;
  beloteScreen.hidden = false;
  beloteTypeSelect.value = beloteTable.game_key;
  beloteLlmMode.hidden = !hasPermission("llm");
  beloteLlmMode.disabled = !beloteTable.llm_available;
  beloteLlmMode.value = beloteTable.llm_mode || "local";
  beloteScore.textContent = `Votre équipe ${beloteTable.scores.hero} — ${beloteTable.scores.opponents} Adversaires`;
  const taker = beloteTable.contract && beloteTable.players.find((player) => player.seat === beloteTable.contract.taker);
  beloteContract.textContent = beloteTable.contract ? `Atout : ${beloteTable.trump} · Contrat : ${beloteTable.contract.amount} ${beloteTable.contract.trump} · Preneur : ${taker?.name || "—"}` : `Carte retournée : ${beloteTable.turned_card || "—"}`;
  const activePlayer = beloteTable.players.find((player) => player.active);
  beloteStatus.textContent = beloteTable.match_finished ? "Match terminé." : beloteTable.phase === "deal_finished" ? beloteTable.last_event : beloteTable.hero_turn ? "À vous de jouer." : activePlayer ? `Au tour de ${activePlayer.name}.` : "Les PNJ réfléchissent…";
  belotePlayers.replaceChildren(...beloteTable.players.map((player) => {
    const item = document.createElement("article");
    item.className = `belote-player belote-player-${player.seat}${player.active ? " active" : ""}${player.taker ? " taker" : ""}`;
    item.innerHTML = "<strong></strong><span></span><em></em>";
    item.querySelector("strong").textContent = player.name;
    item.querySelector("span").textContent = player.active ? "À jouer" : player.taker ? `Preneur · ${player.card_count} cartes` : player.pass_status === "second_round" ? "Refus au 2e tour" : player.pass_status === "folded" ? "A passé" : player.seat === 4 ? "Votre main" : `${player.card_count} cartes`;
    item.querySelector("em").textContent = player.taker ? "Preneur" : player.pass_status === "second_round" ? "2" : player.pass_status === "folded" ? "Couché" : "";
    return item;
  }));
  const displayedTrick = beloteTable.trick.length > 0 ? beloteTable.trick : beloteTable.last_trick;
  beloteTrick.classList.toggle("last-trick", beloteTable.trick.length === 0 && displayedTrick.length > 0);
  const trickCards = displayedTrick.map((entry) => {
    const item = document.createElement("div");
    item.className = `belote-trick-card belote-trick-seat-${entry.seat}`;
    item.append(beloteCard(entry.card));
    return item;
  });

  if (trickCards.length === 0 && beloteTable.turned_card) {
    const turned = document.createElement("div");
    turned.className = "belote-turned-card";
    const label = document.createElement("small");
    label.textContent = "Carte retournée";
    turned.append(label, beloteCard(beloteTable.turned_card));
    beloteTrick.replaceChildren(turned);
  } else {
    beloteTrick.replaceChildren(...trickCards);
  }
  const legalCards = new Map(beloteTable.actions.filter((action) => action.type === "play").map((action) => [action.card, action]));
  beloteHand.replaceChildren(...beloteTable.hand.map((value) => {
    const playable = legalCards.get(value);
    const item = beloteCard(value);
    item.classList.add("belote-card");
    if (playable) {
      item.classList.add("playable");
      item.tabIndex = 0;
      item.setAttribute("role", "button");
      item.onclick = () => submitBeloteAction(playable);
      item.onkeydown = (event) => { if (event.key === "Enter" || event.key === " ") submitBeloteAction(playable); };
    } else {
      item.classList.add("disabled");
    }
    return item;
  }));
  renderBeloteActions();

  beloteHistory.replaceChildren();
  if (beloteTable.last_trick.length > 0) {
    const item = document.createElement("li");
    const cards = beloteTable.last_trick.map((entry) => `${beloteTable.players.find((player) => player.seat === entry.seat)?.name || ""} ${entry.card}`).join(" · ");
    const winner = beloteTable.players.find((player) => player.seat === beloteTable.last_trick_winner)?.name || "";
    item.textContent = `${cards} — ${winner} remporte ${beloteTable.last_trick_points} points.`;
    beloteHistory.append(item);
  }
  beloteTable.deal_history.forEach((deal) => {
    const item = document.createElement("li");
    item.textContent = `Donne ${deal.number} — ${deal.taker} a pris ${deal.amount} ${deal.trump}. ${deal.winner} gagne : votre équipe +${deal.scores.hero}, adversaires +${deal.scores.opponents}.`;
    beloteHistory.append(item);
  });

  if (beloteTable.trick_just_completed) {
    trickClearTimer = setTimeout(() => {
      beloteTrick.replaceChildren();
      beloteTrick.classList.remove("last-trick");
    }, 1200);
  }

  if (!beloteTable.match_finished && beloteTable.phase !== "deal_finished" && !beloteTable.hero_turn) botTimer = setTimeout(advanceBeloteBot, beloteTable.trick_just_completed ? 1800 : 650);
}

async function submitBeloteAction(action) {
  try {
    renderBelote(await api("/api/belote/action", { method: "POST", body: JSON.stringify({ ...action, action: action.type, game_key: beloteTable.game_key }) }));
  } catch (_error) {
    beloteStatus.textContent = "Cette action n’est plus disponible.";
  }
}

async function advanceBeloteBot() {
  try {
    renderBelote(await api("/api/belote/advance-bot", { method: "POST", body: JSON.stringify({ game_key: beloteTable.game_key }) }));
  } catch (_error) {
    restoreBelote();
  }
}

async function nextBeloteDeal() {
  try {
    renderBelote(await api("/api/belote/next-deal", { method: "POST", body: JSON.stringify({ game_key: beloteTable.game_key }) }));
  } catch (_error) {
    beloteStatus.textContent = "Impossible de démarrer la donne suivante.";
  }
}

async function createBelote() {
  try {
    renderBelote(await api("/api/belote", { method: "POST", body: JSON.stringify({ game_key: beloteTypeSelect.value, target_score: Number(beloteTargetSelect.value) }) }));
  } catch (_error) {
    beloteStatus.textContent = "Impossible de créer la partie.";
  }
}

async function resumeBelote() {
  try {
    renderBelote(await api("/api/belote/resume", { method: "POST", body: JSON.stringify({ game_key: beloteTypeSelect.value }) }));
  } catch (_error) {
    beloteStatus.textContent = "Aucune partie à reprendre.";
  }
}

async function leaveBelote() {
  try {
    await api(`/api/belote?game_key=${encodeURIComponent(beloteTable.game_key)}`, { method: "DELETE" });
    beloteTable = null;
    beloteScreen.hidden = true;
    beloteLobby.hidden = false;
    refreshBeloteSaveStatus();
  } catch (_error) {
    beloteStatus.textContent = "Impossible de quitter la partie.";
  }
}

async function setBeloteLlmMode() {
  if (!beloteTable || !beloteTable.llm_available) return;

  try {
    renderBelote(await api("/api/belote/llm-mode", { method: "POST", body: JSON.stringify({ game_key: beloteTable.game_key, mode: beloteLlmMode.value }) }));
  } catch (_error) {
    beloteStatus.textContent = "Impossible de modifier le mode PNJ.";
  }
}

async function restoreSession() {
  const token = sessionStorage.getItem(tokenKey);
  if (!token) return;

  try {
    showDashboard(await api("/api/auth/me"));
  } catch (_error) {
    if (sessionStorage.getItem(tokenKey)) showLogin("Votre session a expiré, reconnectez-vous pour continuer.");
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
    seat.innerHTML = `<div class="seat-heading"><strong></strong><span class="position-badge"></span></div><span class="seat-stack"></span><span class="seat-status"></span><div class="hole-cards"></div><div class="seat-hud"></div>`;
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

    renderHud(seat.querySelector(".seat-hud"), player.hud);
    pokerTable.append(seat);
  });
}

function renderHud(container, hud) {
  if (!hud) return;

  [
    ["H", hud.hands],
    ["VP", `${hud.vpip}%`],
    ["PF", `${hud.pfr}%`],
    ["A", hud.aggressive],
    ["C", hud.calls],
    ["F", hud.folds]
  ].forEach(([label, value]) => {
    const item = document.createElement("span");
    item.innerHTML = `<small></small><strong></strong>`;
    item.querySelector("small").textContent = label;
    item.querySelector("strong").textContent = value;
    container.append(item);
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
    input.inputMode = "decimal";
    input.setAttribute("aria-label", "Montant");
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

function actionText(action) {
  if (!action) return "";
  const amount = action.amount === null || action.amount === undefined ? "" : ` ${money(action.amount)}`;

  return `${action.action}${amount}`;
}

function renderShadow(shadow, playedAction, llmApplied = false) {
  if (!hasPermission("llm") || !shadow || shadow.status !== "available") return null;

  const block = document.createElement("div");
  block.className = `llm-shadow${shadow.diverged ? " diverged" : ""}`;

  const summary = document.createElement("div");
  summary.className = "llm-shadow-summary";
  summary.textContent = llmApplied ? `🤖 Décision LLM : ${actionText(shadow)}` : `Action jouée : ${actionText(playedAction)} · LLM aurait fait : ${actionText(shadow)} · Divergence : ${shadow.diverged ? "oui" : "non"}`;
  block.append(summary);

  if (shadow.short_reason) {
    const reason = document.createElement("p");
    reason.textContent = shadow.short_reason;
    block.append(reason);
  }

  const meta = document.createElement("span");
  const tags = Array.isArray(shadow.reason_tags) && shadow.reason_tags.length > 0 ? ` · ${shadow.reason_tags.join(", ")}` : "";
  const confidence = typeof shadow.confidence === "number" ? ` · ${(shadow.confidence * 100).toFixed(0)}%` : "";
  meta.textContent = `${shadow.model || "LLM"} via ${shadow.provider || "OpenRouter"}${confidence}${tags}`;
  block.append(meta);

  return block;
}

function renderActionItem(item) {
  const line = document.createElement("li");
  const title = document.createElement("span");
  title.textContent = `${item.player} : ${item.action}`;
  line.append(title);

  const shadow = renderShadow(item.llm_shadow, item.played_action, item.llm_applied);
  if (shadow) line.append(shadow);

  return line;
}

function renderTable(nextTable) {
  table = nextTable;
  actionPending = false;
  clearTimeout(botTimer);
  clearTableRetry();
  tableLobby.hidden = true;
  tableScreen.hidden = false;
  if (table.game_key) gameTypeSelect.value = table.game_key;
  tableStatus.textContent = table.hand_finished ? "Main terminée." : table.hero_turn ? "C’est à vous de jouer." : "Action PNJ en cours.";
  handNumber.textContent = `Main ${table.hand_number}`;
  pot.textContent = money(table.pot);
  board.replaceChildren(...table.board.map(card));
  renderPlayers(table.players);
  renderActions();
  renderResult();
  renderLlmMode();
  recentActions.replaceChildren(...(table.hand_actions || table.recent_actions).map(renderActionItem));

  if (!table.hand_finished && !table.hero_turn) {
    // Une requête ne fait jouer qu'un PNJ pour rendre la séquence lisible.
    botTimer = setTimeout(() => advanceBot(), 700);
  }
}

function renderLlmMode() {
  if (!hasPermission("llm")) return;

  const available = Boolean(table.llm_available);
  llmModeSelect.disabled = !available;
  llmModeSelect.value = available ? (table.llm_mode || "llm") : "off";
  llmCredit.hidden = !available;
  if (available) refreshLlmCredit();
}

async function submitAction(action) {
  if (actionPending) return;

  actionPending = true;
  actionPanel.querySelectorAll("button, input").forEach((control) => control.disabled = true);

  try {
    renderTable(await api("/api/table/action", { method: "POST", body: JSON.stringify(action) }));
  } catch (_error) {
    actionPending = false;
    actionPanel.querySelectorAll("button, input").forEach((control) => control.disabled = false);
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

async function setLlmMode() {
  if (!hasPermission("llm") || !table || !table.llm_available) return;

  llmModeSelect.disabled = true;

  try {
    renderTable(await api("/api/table/llm-mode", { method: "POST", body: JSON.stringify({ mode: llmModeSelect.value }) }));
  } catch (_error) {
    tableStatus.textContent = "Impossible de modifier le mode LLM.";
    renderLlmMode();
  }
}

async function refreshLlmCredit() {
  try {
    const credit = await api("/api/llm/credits");
    if (!credit.available || typeof credit.remaining !== "number") {
      llmCredit.textContent = "";
      return;
    }

    llmCredit.textContent = `OR ${credit.remaining.toFixed(2)} $`;
  } catch (_error) {
    llmCredit.textContent = "";
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
    refreshSaveStatus();
  } catch (_error) {
    tableStatus.textContent = "Impossible de quitter la table.";
  }
}

async function resetTable() {
  resetTableButton.disabled = true;

  try {
    await api("/api/table", { method: "DELETE" });
    clearExtract();
    renderTable(await api("/api/table", { method: "POST", body: JSON.stringify({ game_key: table?.game_key || gameTypeSelect.value }) }));
  } catch (_error) {
    tableStatus.textContent = "Impossible de démarrer une nouvelle partie.";
  } finally {
    resetTableButton.disabled = false;
  }
}

async function createNewTable() {
  newTableButton.disabled = true;
  resumeTableButton.disabled = true;

  try {
    renderTable(await api("/api/table", { method: "POST", body: JSON.stringify({ game_key: gameTypeSelect.value }) }));
  } catch (_error) {
    tableStatus.textContent = "Impossible de créer la table.";
  } finally {
    newTableButton.disabled = false;
    resumeTableButton.disabled = false;
  }
}

async function resumeTable() {
  resumeTableButton.disabled = true;
  newTableButton.disabled = true;

  try {
    renderTable(await api("/api/table/resume", { method: "POST", body: JSON.stringify({ game_key: gameTypeSelect.value }) }));
  } catch (_error) {
    tableStatus.textContent = "Aucune partie à reprendre.";
    refreshSaveStatus();
  } finally {
    resumeTableButton.disabled = false;
    newTableButton.disabled = false;
  }
}

async function extractHands() {
  if (!hasPermission("llm")) return;
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

function closeExtract() {
  extractPanel.hidden = true;
}

async function requestCoaching() {
  if (!hasPermission("llm")) return;
  coachingButton.disabled = true;

  try {
    const advice = await api("/api/llm/coaching", { method: "POST", body: "{}" });
    coachingAdvice.textContent = advice.advice;
    coachingWhy.textContent = advice.why;
    coachingDialog.showModal();
  } catch (_error) {
    tableStatus.textContent = "Impossible de générer un conseil.";
  } finally {
    coachingButton.disabled = false;
  }
}

function mrWhiteNode(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function mrWhiteButton(text, className, click) {
  const button = mrWhiteNode("button", className, text);
  button.type = "button";
  button.onclick = click;
  return button;
}

function renderMrWhitePlayerFields(names = null) {
  const previous = names || Array.from(mrWhitePlayerFields.querySelectorAll("input")).map((input) => input.value);
  const count = Number(mrWhitePlayerCount.value);
  const previousSpyCount = Number(mrWhiteSpyCount.value) || 1;
  mrWhitePlayerFields.replaceChildren();
  mrWhiteSpyCount.replaceChildren();

  for (let spyCount = 1; spyCount * 2 < count; spyCount += 1) {
    const option = new Option(`${spyCount} espion${spyCount > 1 ? "s" : ""}`, spyCount);
    option.selected = spyCount === previousSpyCount;
    mrWhiteSpyCount.append(option);
  }

  for (let index = 0; index < count; index += 1) {
    const label = mrWhiteNode("label", "", `Joueur ${index + 1}`);
    const input = document.createElement("input");
    input.type = "text";
    input.name = "player";
    input.maxLength = 40;
    input.required = true;
    input.autocomplete = "off";
    input.placeholder = `Prénom du joueur ${index + 1}`;
    input.value = previous[index] || "";
    label.append(input);
    mrWhitePlayerFields.append(label);
  }
}

async function restoreMrWhite() {
  if (!hasPermission("mr_white")) return;

  try {
    renderMrWhite(await api("/api/mr-white"));
  } catch (error) {
    if (error.message === "table_not_found") {
      mrWhiteState = null;
      mrWhiteLobby.hidden = false;
      mrWhiteGame.hidden = true;
      return;
    }

    if (error.message !== "session_expired") mrWhiteStatus.textContent = "Impossible de retrouver la partie.";
  }
}

async function createMrWhite(event) {
  event.preventDefault();
  const players = Array.from(mrWhitePlayerFields.querySelectorAll("input")).map((input) => input.value.trim());
  const spyCount = Number(mrWhiteSpyCount.value);
  mrWhiteStatus.textContent = "";

  try {
    renderMrWhite(await api("/api/mr-white", { method: "POST", body: JSON.stringify({ players, spy_count: spyCount }) }));
  } catch (error) {
    mrWhiteStatus.textContent = error.message === "invalid_players" ? "Utilisez de 3 à 10 noms différents, de 40 caractères maximum." : error.message === "invalid_spy_count" ? "Le nombre d’espions doit être inférieur à la moitié des joueurs." : "Impossible de lancer la partie.";
  }
}

function mrWhiteRoleLabel(role) {
  return { civil: "Civil", spy: "Espion", mr_white: "Mr. White" }[role] || "Rôle inconnu";
}

function mrWhiteOrderedPlayers(state) {
  return [...state.players].sort((left, right) => left.position - right.position);
}

function renderMrWhiteOrder(state, title = "Ordre de parole") {
  const section = mrWhiteNode("section", "mr-white-order");
  section.append(mrWhiteNode("h3", "", title));
  const list = mrWhiteNode("ol", "mr-white-order-list");

  mrWhiteOrderedPlayers(state).forEach((player) => {
    const item = mrWhiteNode("li", player.active ? "" : "eliminated");
    item.append(mrWhiteNode("strong", "", player.name));
    if (!player.active) item.append(mrWhiteNode("span", "", player.role ? `Éliminé · ${mrWhiteRoleLabel(player.role)}` : "Éliminé"));
    list.append(item);
  });

  section.append(list);
  return section;
}

function renderMrWhite(nextState) {
  mrWhiteState = nextState;
  mrWhiteLobby.hidden = true;
  mrWhiteGame.hidden = false;
  mrWhiteRound.textContent = nextState.phase === "reveal" ? "Distribution des mots" : `Tour ${nextState.round}`;
  mrWhiteStage.classList.remove("secret-visible");
  mrWhiteStage.replaceChildren();

  if (nextState.phase === "reveal") renderMrWhiteReveal(nextState);
  if (nextState.phase === "vote") renderMrWhiteVote(nextState);
  if (nextState.phase === "elimination") renderMrWhiteElimination(nextState);
  if (nextState.phase === "finished") renderMrWhiteFinished(nextState);
}

function renderMrWhiteReveal(state) {
  const player = state.reveal_player;
  mrWhiteStage.append(
    mrWhiteNode("p", "eyebrow", `Joueur ${player.number} sur ${player.total}`),
    mrWhiteNode("h2", "mr-white-main-title", `Passez le téléphone à ${player.name}`),
    mrWhiteNode("p", "mr-white-instruction", "Personne d’autre ne doit regarder l’écran."),
    mrWhiteButton("Voir mon mot", "primary-button mr-white-main-action", revealMrWhiteSecret)
  );
}

async function revealMrWhiteSecret() {
  try {
    const secret = await api("/api/mr-white/secret", { method: "POST", body: "{}" });
    showMrWhiteSecret(secret, "J’ai mémorisé · masquer", confirmMrWhiteReveal);
  } catch (_error) {
    mrWhiteStatus.textContent = "Impossible d’afficher le mot.";
  }
}

function showMrWhiteSecret(secret, buttonLabel, click) {
  mrWhiteStage.replaceChildren();
  mrWhiteStage.classList.add("secret-visible");

  if (secret.role === "mr_white") {
    mrWhiteStage.append(
      mrWhiteNode("p", "eyebrow", secret.name),
      mrWhiteNode("h2", "mr-white-secret-word", "Vous êtes Mr. White"),
      mrWhiteNode("p", "mr-white-instruction", "Vous n’avez aucun mot. Écoutez bien les autres et improvisez.")
    );
  } else {
    mrWhiteStage.append(
      mrWhiteNode("p", "eyebrow", secret.name),
      mrWhiteNode("p", "mr-white-instruction", "Votre mot secret est"),
      mrWhiteNode("h2", "mr-white-secret-word", secret.word)
    );
  }

  mrWhiteStage.append(mrWhiteButton(buttonLabel, "primary-button mr-white-main-action", click));
}

async function confirmMrWhiteReveal() {
  mrWhiteStage.classList.remove("secret-visible");
  await mrWhiteAction({ action: "confirm_reveal" });
}

function renderMrWhiteVote(state) {
  mrWhiteStage.append(
    mrWhiteNode("p", "eyebrow", `Tour ${state.round}`),
    mrWhiteNode("h2", "mr-white-main-title", "Décrivez votre mot, puis éliminez un joueur"),
    renderMrWhiteOrder(state)
  );
  mrWhiteStage.append(mrWhiteButton("Revoir mon mot", "leave-table-button mr-white-review-button", () => renderMrWhiteReviewChoice(state)));

  const choices = mrWhiteNode("div", "mr-white-player-choices");
  mrWhiteOrderedPlayers(state).filter((player) => player.active).forEach((player) => {
    choices.append(mrWhiteButton(player.name, "mr-white-player-button", () => {
      if (confirm(`Le groupe élimine ${player.name} ?`)) mrWhiteAction({ action: "eliminate", player_id: player.id });
    }));
  });
  mrWhiteStage.append(mrWhiteNode("h3", "mr-white-choice-title", "Qui est éliminé ?"), choices);
}

function renderMrWhiteReviewChoice(state) {
  mrWhiteStage.replaceChildren(
    mrWhiteNode("p", "eyebrow", "Rappel privé"),
    mrWhiteNode("h2", "mr-white-main-title", "Qui veut revoir son mot ?"),
    mrWhiteNode("p", "mr-white-instruction", "Choisissez le joueur, puis passez-lui le téléphone.")
  );
  const choices = mrWhiteNode("div", "mr-white-player-choices");
  mrWhiteOrderedPlayers(state).filter((player) => player.active).forEach((player) => {
    choices.append(mrWhiteButton(player.name, "mr-white-player-button", () => prepareMrWhiteReview(player)));
  });
  mrWhiteStage.append(choices, mrWhiteButton("Retour au vote", "leave-table-button mr-white-review-button", () => renderMrWhite(state)));
}

function prepareMrWhiteReview(player) {
  mrWhiteStage.replaceChildren(
    mrWhiteNode("p", "eyebrow", "Rappel privé"),
    mrWhiteNode("h2", "mr-white-main-title", `Passez le téléphone à ${player.name}`),
    mrWhiteNode("p", "mr-white-instruction", "Personne d’autre ne doit regarder l’écran."),
    mrWhiteButton("Revoir mon mot", "primary-button mr-white-main-action", () => revealMrWhiteReview(player.id)),
    mrWhiteButton("Annuler", "leave-table-button mr-white-review-button", () => renderMrWhite(mrWhiteState))
  );
}

async function revealMrWhiteReview(playerId) {
  try {
    const secret = await api("/api/mr-white/review-secret", { method: "POST", body: JSON.stringify({ player_id: playerId }) });
    showMrWhiteSecret(secret, "Masquer et revenir au vote", () => renderMrWhite(mrWhiteState));
  } catch (_error) {
    renderMrWhite(mrWhiteState);
  }
}

function renderMrWhiteElimination(state) {
  const player = state.eliminated;
  mrWhiteStage.append(
    mrWhiteNode("p", "eyebrow", "Rôle révélé"),
    mrWhiteNode("h2", "mr-white-main-title", player.name),
    mrWhiteNode("strong", `mr-white-role role-${player.role}`, mrWhiteRoleLabel(player.role))
  );

  if (player.role === "mr_white" && state.guess_result === null) {
    const actions = mrWhiteNode("div", "mr-white-guess-actions");
    actions.append(
      mrWhiteButton("Bonne réponse", "primary-button", () => mrWhiteAction({ action: "mr_white_guess", accepted: true })),
      mrWhiteButton("Mauvaise réponse", "leave-table-button", () => mrWhiteAction({ action: "mr_white_guess", accepted: false }))
    );
    mrWhiteStage.append(
      mrWhiteNode("p", "mr-white-instruction", "Mr. White annonce maintenant le mot des civils à voix haute. Le groupe valide sa réponse."),
      actions
    );
    return;
  }

  mrWhiteStage.append(mrWhiteButton("Tour suivant", "primary-button mr-white-main-action", () => mrWhiteAction({ action: "next_round" })));
}

function renderMrWhiteFinished(state) {
  const messages = {
    both_infiltrators_eliminated: "Mr. White et l’espion ont tous les deux été éliminés.",
    two_players_remaining: "Il ne reste que deux joueurs. Découvrez tous les rôles.",
    mr_white_guess_accepted: "Le groupe valide la proposition de Mr. White."
  };
  const roles = mrWhiteNode("div", "mr-white-final-roles");

  mrWhiteOrderedPlayers(state).forEach((player) => {
    const row = mrWhiteNode("div", `mr-white-final-player role-${player.role}`);
    row.append(mrWhiteNode("strong", "", player.name), mrWhiteNode("span", "", mrWhiteRoleLabel(player.role)));
    roles.append(row);
  });

  const words = mrWhiteNode("div", "mr-white-final-words");
  words.append(
    mrWhiteNode("p", "", `Mot des civils : ${state.words.civil}`),
    mrWhiteNode("p", "", `Mot de l’espion : ${state.words.spy}`)
  );
  const actions = mrWhiteNode("div", "mr-white-end-actions");
  actions.append(
    mrWhiteButton("Rejouer avec les mêmes noms", "primary-button", restartMrWhite),
    mrWhiteButton("Changer les joueurs", "leave-table-button", changeMrWhitePlayers)
  );
  mrWhiteStage.append(
    mrWhiteNode("p", "eyebrow", "Partie terminée"),
    mrWhiteNode("h2", "mr-white-main-title", messages[state.end_reason] || "Partie terminée"),
    roles,
    words,
    actions
  );
}

async function mrWhiteAction(body) {
  try {
    renderMrWhite(await api("/api/mr-white/action", { method: "POST", body: JSON.stringify(body) }));
  } catch (_error) {
    mrWhiteStatus.textContent = "Cette action n’est plus disponible.";
  }
}

async function restartMrWhite() {
  if (mrWhiteState && mrWhiteState.phase !== "finished" && !confirm("Recommencer immédiatement avec les mêmes joueurs ?")) return;

  try {
    renderMrWhite(await api("/api/mr-white/restart", { method: "POST", body: "{}" }));
  } catch (_error) {
    mrWhiteStatus.textContent = "Impossible de recommencer la partie.";
  }
}

async function changeMrWhitePlayers() {
  if (mrWhiteState && mrWhiteState.phase !== "finished" && !confirm("Arrêter cette partie et modifier les joueurs ?")) return;
  const names = mrWhiteState ? [...mrWhiteState.players].sort((left, right) => left.id - right.id).map((player) => player.name) : [];
  const spyCount = mrWhiteState ? mrWhiteState.spy_count : 1;

  try {
    await api("/api/mr-white", { method: "DELETE" });
    mrWhiteState = null;
    mrWhitePlayerCount.value = String(Math.min(10, Math.max(3, names.length || 5)));
    mrWhiteSpyCount.value = String(spyCount);
    renderMrWhitePlayerFields(names);
    mrWhiteLobby.hidden = false;
    mrWhiteGame.hidden = true;
  } catch (_error) {
    mrWhiteStatus.textContent = "Impossible d’arrêter la partie.";
  }
}

function permissionsFromForm(form) {
  return Array.from(form.querySelectorAll("input[name='permissions']:checked")).map((input) => input.value);
}

async function loadAdminUsers() {
  if (!hasPermission("admin")) return;

  try {
    const data = await api("/api/admin/users");
    renderAdminUsers(data.users || []);
  } catch (_error) {
    adminStatus.textContent = "Impossible de charger les utilisateurs.";
  }
}

function permissionControl(permission, checked) {
  const label = document.createElement("label");
  const input = document.createElement("input");
  input.type = "checkbox";
  input.value = permission;
  input.checked = checked;
  label.append(input, document.createTextNode(permission.toUpperCase()));
  return label;
}

function lockedLabel(lockedUntil) {
  if (!lockedUntil) return "Actif";

  const date = new Date(lockedUntil);
  if (Number.isNaN(date.getTime()) || date <= new Date()) return "Actif";
  return `Bloqué jusqu’au ${date.toLocaleString("fr-FR")}`;
}

function renderAdminUsers(users) {
  usersTableBody.replaceChildren(...users.map((user) => {
    const row = document.createElement("tr");
    const nameCell = document.createElement("td");
    const permissionsCell = document.createElement("td");
    const statusCell = document.createElement("td");
    const passwordCell = document.createElement("td");
    const actionsCell = document.createElement("td");
    const name = document.createElement("strong");
    const permissions = document.createElement("div");
    const password = document.createElement("input");
    const actions = document.createElement("div");
    const save = document.createElement("button");
    const remove = document.createElement("button");

    name.textContent = user.username;
    nameCell.append(name);
    permissions.className = "row-permissions";
    permissionNames.forEach((permission) => permissions.append(permissionControl(permission, user.permissions.includes(permission))));
    permissionsCell.append(permissions);
    statusCell.textContent = lockedLabel(user.locked_until);
    password.type = "password";
    password.placeholder = "Reset optionnel";
    password.autocomplete = "new-password";
    passwordCell.append(password);
    actions.className = "row-actions";
    save.type = "button";
    save.textContent = "Enregistrer";
    save.onclick = () => saveUser(user.username, permissions, password);
    remove.type = "button";
    remove.textContent = "Supprimer";
    remove.onclick = () => deleteUser(user.username);
    actions.append(save);
    if (lockedLabel(user.locked_until) !== "Actif") {
      const unlock = document.createElement("button");
      unlock.type = "button";
      unlock.textContent = "Débloquer";
      unlock.onclick = () => unlockUser(user.username, permissions, password);
      actions.append(unlock);
    }
    actions.append(remove);
    actionsCell.append(actions);
    row.append(nameCell, permissionsCell, statusCell, passwordCell, actionsCell);
    return row;
  }));
}

async function saveUser(username, permissionsNode, passwordInput) {
  const permissions = Array.from(permissionsNode.querySelectorAll("input:checked")).map((input) => input.value);
  const body = { permissions };
  if (passwordInput.value) body.password = passwordInput.value;

  try {
    await api(`/api/admin/users/${encodeURIComponent(username)}`, { method: "PUT", body: JSON.stringify(body) });
    adminStatus.textContent = "Utilisateur mis à jour.";
    adminStatus.classList.add("success");
    loadAdminUsers();
  } catch (error) {
    adminStatus.classList.remove("success");
    adminStatus.textContent = error.message === "last_admin" ? "Impossible de retirer le dernier admin." : "Impossible de mettre à jour cet utilisateur.";
  }
}

async function unlockUser(username, permissionsNode, passwordInput) {
  const permissions = Array.from(permissionsNode.querySelectorAll("input:checked")).map((input) => input.value);
  const body = { permissions, unlock: true };
  if (passwordInput.value) body.password = passwordInput.value;

  try {
    await api(`/api/admin/users/${encodeURIComponent(username)}`, { method: "PUT", body: JSON.stringify(body) });
    adminStatus.textContent = "Utilisateur débloqué.";
    adminStatus.classList.add("success");
    loadAdminUsers();
  } catch (_error) {
    adminStatus.classList.remove("success");
    adminStatus.textContent = "Impossible de débloquer cet utilisateur.";
  }
}

async function deleteUser(username) {
  if (!confirm(`Supprimer définitivement l'utilisateur "${username}" ?`)) return;

  try {
    await api(`/api/admin/users/${encodeURIComponent(username)}`, { method: "DELETE" });
    adminStatus.textContent = "Utilisateur supprimé.";
    adminStatus.classList.add("success");
    loadAdminUsers();
  } catch (error) {
    adminStatus.classList.remove("success");
    adminStatus.textContent = error.message === "last_admin" ? "Impossible de supprimer le dernier admin." : "Impossible de supprimer cet utilisateur.";
  }
}

function passwordErrorMessage(error) {
  return {
    missing_current_password: "Renseignez votre mot de passe actuel.",
    missing_new_password: "Renseignez un nouveau mot de passe.",
    invalid_current_password: "Le mot de passe actuel est incorrect.",
    invalid_new_password: "Le nouveau mot de passe doit contenir au moins 12 caractères et ne pas contenir de retour à la ligne.",
    password_update_failed: "Erreur serveur pendant la mise à jour du mot de passe."
  }[error.message] || "Impossible de modifier le mot de passe.";
}

function loginErrorMessage(error) {
  if (error.message !== "locked") return "Utilisateur ou mot de passe incorrect.";
  if (!error.lockedUntil) return "Compte bloqué pendant 12 heures après 5 échecs. Contactez un admin pour le débloquer.";

  const date = new Date(error.lockedUntil);
  if (Number.isNaN(date.getTime())) return "Compte bloqué pendant 12 heures après 5 échecs. Contactez un admin pour le débloquer.";
  return `Compte bloqué jusqu’au ${date.toLocaleString("fr-FR")}. Contactez un admin pour le débloquer.`;
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
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      const error = new Error(body.error || "invalid_credentials");
      error.lockedUntil = body.locked_until;
      throw error;
    }
    const nextSession = await response.json();
    sessionStorage.setItem(tokenKey, nextSession.token);
    showDashboard(nextSession);
  } catch (error) {
    authStatus.textContent = loginErrorMessage(error);
  } finally {
    loginSubmit.disabled = false;
  }
});

function setMenuCollapsed(collapsed) {
  dashboard.classList.toggle("menu-collapsed", collapsed);
  menuToggle.setAttribute("aria-expanded", String(!collapsed));
  menuToggle.setAttribute("aria-label", collapsed ? "Déplier le menu" : "Réduire le menu");
  menuToggle.querySelector("span").textContent = collapsed ? "›" : "‹";
}

menuToggle.addEventListener("click", () => {
  setMenuCollapsed(!dashboard.classList.contains("menu-collapsed"));
});

window.addEventListener("scroll", () => {
  const scrollY = window.scrollY;
  if (!dashboard.hidden && window.matchMedia("(max-width: 700px)").matches && scrollY > previousScrollY) setMenuCollapsed(true);
  previousScrollY = scrollY;
}, { passive: true });

[pokerNav, beloteNav, mrWhiteNav, adminNav, accountNav].forEach((nav) => nav.addEventListener("click", () => showView(nav.dataset.view)));

passwordForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  passwordStatus.textContent = "";

  try {
    await api("/api/auth/password", { method: "POST", body: JSON.stringify(Object.fromEntries(new FormData(passwordForm))) });
    passwordForm.reset();
    passwordStatus.classList.add("success");
    passwordStatus.textContent = "Mot de passe mis à jour.";
  } catch (error) {
    passwordStatus.classList.remove("success");
    passwordStatus.textContent = passwordErrorMessage(error);
  }
});

userCreateForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  adminStatus.textContent = "";

  const body = Object.fromEntries(new FormData(userCreateForm));
  body.permissions = permissionsFromForm(userCreateForm);

  try {
    await api("/api/admin/users", { method: "POST", body: JSON.stringify(body) });
    userCreateForm.reset();
    userCreateForm.querySelector("input[value='poker']").checked = true;
    adminStatus.classList.add("success");
    adminStatus.textContent = "Utilisateur créé.";
    loadAdminUsers();
  } catch (error) {
    adminStatus.classList.remove("success");
    adminStatus.textContent = error.message === "already_exists" ? "Cet utilisateur existe déjà." : "Impossible de créer cet utilisateur.";
  }
});

newTableButton.addEventListener("click", createNewTable);
resumeTableButton.addEventListener("click", resumeTable);
gameTypeSelect.addEventListener("change", refreshSaveStatus);

leaveTableButton.addEventListener("click", leaveTable);
resetTableButton.addEventListener("click", resetTable);
llmModeSelect.addEventListener("change", setLlmMode);
extractButton.addEventListener("click", extractHands);
copyExtractButton.addEventListener("click", copyExtract);
closeExtractButton.addEventListener("click", closeExtract);
coachingButton.addEventListener("click", requestCoaching);
newBeloteButton.addEventListener("click", createBelote);
resumeBeloteButton.addEventListener("click", resumeBelote);
leaveBeloteButton.addEventListener("click", leaveBelote);
beloteTypeSelect.addEventListener("change", refreshBeloteSaveStatus);
beloteLlmMode.addEventListener("change", setBeloteLlmMode);
mrWhitePlayerCount.addEventListener("change", () => renderMrWhitePlayerFields());
mrWhiteForm.addEventListener("submit", createMrWhite);
mrWhiteRestart.addEventListener("click", restartMrWhite);
mrWhiteChangePlayers.addEventListener("click", changeMrWhitePlayers);
logoutButton.addEventListener("click", logout);

renderMrWhitePlayerFields();
restoreSession();
