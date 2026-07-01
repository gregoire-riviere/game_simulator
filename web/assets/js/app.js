// Le token ne vit que dans l'onglet courant : fermer le navigateur déconnecte l'utilisateur.
const tokenKey = "game-simulator-token";
const permissionNames = ["admin", "poker", "llm"];
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
const adminNav = document.getElementById("admin-nav");
const adminNavLabel = document.getElementById("admin-nav-label");
const accountNav = document.getElementById("account-nav");
const pokerPage = document.getElementById("poker-page");
const adminPage = document.getElementById("admin-page");
const accountPage = document.getElementById("account-page");
const passwordForm = document.getElementById("password-form");
const passwordStatus = document.getElementById("password-status");
const userCreateForm = document.getElementById("user-create-form");
const adminStatus = document.getElementById("admin-status");
const usersTableBody = document.getElementById("users-table-body");
const newTableButton = document.getElementById("new-table-button");
const resumeTableButton = document.getElementById("resume-table-button");
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
const coachingButton = document.getElementById("coaching-button");
const coachingDialog = document.getElementById("coaching-dialog");
const coachingAdvice = document.getElementById("coaching-advice");
const coachingWhy = document.getElementById("coaching-why");
const handResult = document.getElementById("hand-result");
const handResultReason = document.getElementById("hand-result-reason");
const handResultWinners = document.getElementById("hand-result-winners");
let session = null;
let table = null;
let botTimer = null;
let tableRetryTimer = null;
let tableRetrySeconds = 0;
let actionPending = false;

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
  if (hasPermission("admin")) return "admin";
  return "account";
}

function renderAccess() {
  pokerNav.hidden = !hasPermission("poker");
  adminNav.hidden = !hasPermission("admin");
  adminNavLabel.hidden = !hasPermission("admin");
  llmControls.hidden = !hasPermission("llm");
  showView(defaultView());
}

function showView(view) {
  const allowedView = view === "admin" && !hasPermission("admin") ? defaultView() : view === "poker" && !hasPermission("poker") ? defaultView() : view;
  const pages = { poker: pokerPage, admin: adminPage, account: accountPage };
  const navs = { poker: pokerNav, admin: adminNav, account: accountNav };

  Object.entries(pages).forEach(([name, page]) => page.hidden = name !== allowedView);
  Object.entries(navs).forEach(([name, nav]) => {
    nav.classList.toggle("active", name === allowedView);
    if (name === allowedView) nav.setAttribute("aria-current", "page");
    else nav.removeAttribute("aria-current");
  });

  if (allowedView === "admin") loadAdminUsers();
  if (allowedView === "poker") restoreTable();
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
    const status = await api("/api/table/save");
    resumeTableButton.hidden = !status.has_save;
  } catch (_error) {
    resumeTableButton.hidden = true;
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
    renderTable(await api("/api/table", { method: "POST", body: "{}" }));
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
    renderTable(await api("/api/table", { method: "POST", body: "{}" }));
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
    renderTable(await api("/api/table/resume", { method: "POST", body: "{}" }));
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

menuToggle.addEventListener("click", () => {
  const collapsed = dashboard.classList.toggle("menu-collapsed");
  menuToggle.setAttribute("aria-expanded", String(!collapsed));
  menuToggle.querySelector("span").textContent = collapsed ? "›" : "‹";
});

[pokerNav, adminNav, accountNav].forEach((nav) => nav.addEventListener("click", () => showView(nav.dataset.view)));

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

leaveTableButton.addEventListener("click", leaveTable);
resetTableButton.addEventListener("click", resetTable);
llmModeSelect.addEventListener("change", setLlmMode);
extractButton.addEventListener("click", extractHands);
copyExtractButton.addEventListener("click", copyExtract);
coachingButton.addEventListener("click", requestCoaching);
logoutButton.addEventListener("click", logout);

restoreSession();
