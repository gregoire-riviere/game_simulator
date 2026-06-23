const tokenKey = "game-simulator-token";
const appShell = document.querySelector(".app-shell");
const loginScreen = document.getElementById("login-screen");
const dashboard = document.getElementById("dashboard");
const loginForm = document.getElementById("login-form");
const authStatus = document.getElementById("auth-status");
const loginSubmit = loginForm.querySelector("button");
const sessionUser = document.getElementById("session-user");
const menuToggle = document.getElementById("menu-toggle");
const newGameToggle = document.getElementById("new-game-toggle");
const newGameForm = document.getElementById("new-game-form");
const setupStatus = document.getElementById("game-setup-status");
const gameSummary = document.getElementById("game-summary");

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
}

async function restoreSession() {
  const token = sessionStorage.getItem(tokenKey);

  if (!token) return;

  try {
    const response = await fetch("/api/auth/me", {
      headers: { authorization: `Bearer ${token}` }
    });

    if (!response.ok) throw new Error("invalid_session");

    const session = await response.json();
    showDashboard(session.user);
  } catch (_error) {
    showLogin();
  }
}

loginForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  authStatus.classList.remove("success");
  authStatus.textContent = "";
  loginSubmit.disabled = true;

  try {
    const response = await fetch("/api/auth/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(Object.fromEntries(new FormData(loginForm)))
    });

    if (!response.ok) throw new Error("invalid_credentials");

    const session = await response.json();
    sessionStorage.setItem(tokenKey, session.token);
    showDashboard(session.user);
  } catch (_error) {
    authStatus.textContent = "Utilisateur ou mot de passe incorrect.";
  } finally {
    loginSubmit.disabled = false;
  }
});

menuToggle.addEventListener("click", () => {
  const collapsed = dashboard.classList.toggle("menu-collapsed");
  menuToggle.setAttribute("aria-expanded", String(!collapsed));
  menuToggle.setAttribute("aria-label", collapsed ? "Ouvrir le menu" : "Réduire le menu");
  menuToggle.querySelector("span").textContent = collapsed ? "›" : "‹";
});

newGameToggle.addEventListener("click", () => {
  const isOpen = !newGameForm.hidden;
  newGameForm.hidden = isOpen;
  newGameToggle.setAttribute("aria-expanded", String(!isOpen));
  newGameToggle.querySelector("span:last-child").textContent = isOpen ? "→" : "×";

  if (!isOpen) document.getElementById("players").focus();
});

newGameForm.addEventListener("submit", (event) => {
  event.preventDefault();
  const values = Object.fromEntries(new FormData(newGameForm));
  const players = Number(values.players);
  const stack = Number(values.stack);
  const smallBlind = Number(values["small-blind"]);
  const bigBlind = Number(values["big-blind"]);

  setupStatus.classList.remove("success");

  if (![players, stack, smallBlind, bigBlind].every(Number.isInteger) || players < 2 || players > 9 || stack < 1 || smallBlind < 1 || bigBlind <= smallBlind) {
    gameSummary.hidden = true;
    setupStatus.textContent = "Indiquez 2 à 9 joueurs, des montants entiers positifs et une big blind supérieure à la small blind.";
    return;
  }

  document.getElementById("summary-players").textContent = players;
  document.getElementById("summary-stack").textContent = stack.toLocaleString("fr-FR");
  document.getElementById("summary-blinds").textContent = `${smallBlind} / ${bigBlind}`;
  gameSummary.hidden = false;
  setupStatus.classList.add("success");
  setupStatus.textContent = "Paramètres enregistrés localement.";
});

restoreSession();
