document.addEventListener("DOMContentLoaded", () => {
  if (typeof beloteLobby === "undefined") return;

  const normalSetup = beloteLobby.querySelector(".card-heading");
  const onlinePanel = document.createElement("section");
  onlinePanel.className = "activity-card";
  onlinePanel.innerHTML = `
    <h2>Jouer en ligne</h2>
    <p>Créez un salon et partagez son code, ou rejoignez un salon existant.</p>
    <div class="lobby-actions">
      <button id="create-online-belote" class="primary-button" type="button">Créer un salon</button>
      <input id="join-online-belote-code" type="text" maxlength="5" placeholder="Code" autocomplete="off" aria-label="Code du salon" />
      <button id="join-online-belote" class="leave-table-button" type="button">Rejoindre</button>
    </div>
    <div id="online-belote-waiting" hidden>
      <p>Code du salon : <strong id="online-belote-code"></strong></p>
      <p id="online-belote-players"></p>
      <div class="lobby-actions">
        <button id="start-online-belote" class="primary-button" type="button" hidden>Lancer avec les bots</button>
        <button id="leave-online-belote" class="leave-table-button" type="button">Quitter le salon</button>
      </div>
    </div>
    <p id="online-belote-status" class="form-status" role="status" aria-live="polite"></p>
  `;
  beloteLobby.append(onlinePanel);

  const createButton = document.getElementById("create-online-belote");
  const joinButton = document.getElementById("join-online-belote");
  const joinCode = document.getElementById("join-online-belote-code");
  const waiting = document.getElementById("online-belote-waiting");
  const code = document.getElementById("online-belote-code");
  const players = document.getElementById("online-belote-players");
  const startButton = document.getElementById("start-online-belote");
  const leaveLobbyButton = document.getElementById("leave-online-belote");
  const status = document.getElementById("online-belote-status");

  let onlinePollTimer = null;
  const soloRestoreBelote = restoreBelote;
  const soloSubmitBeloteAction = submitBeloteAction;
  const soloAdvanceBeloteBot = advanceBeloteBot;
  const soloNextBeloteDeal = nextBeloteDeal;
  const soloLeaveBelote = leaveBelote;
  const soloRenderBeloteActions = renderBeloteActions;

  function clearOnlinePoll() {
    clearTimeout(onlinePollTimer);
    onlinePollTimer = null;
  }

  function scheduleOnlinePoll(delay = 1000) {
    clearOnlinePoll();
    onlinePollTimer = setTimeout(refreshOnlineState, delay);
  }

  function resetOnlineLobby() {
    clearOnlinePoll();
    waiting.hidden = true;
    normalSetup.hidden = false;
    status.textContent = "";
  }

  function renderOnlineWaiting(state) {
    clearTimeout(botTimer);
    beloteScreen.hidden = true;
    beloteLobby.hidden = false;
    normalSetup.hidden = true;
    waiting.hidden = false;
    code.textContent = state.code;
    players.textContent = state.players.filter((player) => !player.empty).map((player) => player.self ? `${player.name} (vous)` : player.name).join(" · ");
    startButton.hidden = !state.is_host;
    startButton.textContent = state.player_count < 4 ? `Lancer avec ${4 - state.player_count} bot${state.player_count === 3 ? "" : "s"}` : "Lancer la partie";
    status.textContent = state.player_count === 1 ? "En attente d’autres joueurs…" : `${state.player_count}/4 joueurs connectés.`;
    scheduleOnlinePoll();
  }

  function renderOnlineState(state) {
    if (state.status === "waiting") {
      renderOnlineWaiting(state);
      return;
    }

    normalSetup.hidden = false;
    waiting.hidden = true;
    renderBelote(state);
    scheduleOnlinePoll(state.hero_turn ? 1500 : 800);
  }

  async function refreshOnlineState() {
    try {
      renderOnlineState(await api("/api/belote-online/state"));
    } catch (error) {
      if (error.message === "lobby_not_found") resetOnlineLobby();
      else if (error.message !== "session_expired") scheduleOnlinePoll(1500);
    }
  }

  async function createOnlineLobby() {
    status.textContent = "Création du salon…";
    try {
      const state = await api("/api/belote-online/create", {
        method: "POST",
        body: JSON.stringify({ game_key: beloteTypeSelect.value, target_score: Number(beloteTargetSelect.value) })
      });
      renderOnlineWaiting(state);
    } catch (_error) {
      status.textContent = "Impossible de créer le salon.";
    }
  }

  async function joinOnlineLobby() {
    const value = joinCode.value.trim().toUpperCase();
    if (!value) {
      status.textContent = "Saisissez le code du salon.";
      return;
    }

    status.textContent = "Connexion au salon…";
    try {
      renderOnlineWaiting(await api("/api/belote-online/join", { method: "POST", body: JSON.stringify({ code: value }) }));
    } catch (error) {
      status.textContent = error.message === "lobby_full" ? "Ce salon est complet." : error.message === "game_already_started" ? "La partie a déjà commencé." : "Salon introuvable.";
    }
  }

  async function startOnlineGame() {
    try {
      renderOnlineState(await api("/api/belote-online/start", { method: "POST", body: "{}" }));
    } catch (_error) {
      status.textContent = "Impossible de lancer la partie.";
    }
  }

  async function leaveOnlineLobby() {
    try {
      await api("/api/belote-online/leave", { method: "DELETE" });
    } catch (_error) {
      status.textContent = "Impossible de quitter le salon.";
      return;
    }

    beloteTable = null;
    beloteScreen.hidden = true;
    beloteLobby.hidden = false;
    resetOnlineLobby();
    refreshBeloteSaveStatus();
  }

  restoreBelote = async function() {
    if (!hasPermission("belote")) return;

    try {
      renderOnlineState(await api("/api/belote-online/state"));
    } catch (error) {
      if (error.message === "lobby_not_found") await soloRestoreBelote();
    }
  };

  submitBeloteAction = async function(action) {
    if (!beloteTable?.online) return soloSubmitBeloteAction(action);

    try {
      renderOnlineState(await api("/api/belote-online/action", { method: "POST", body: JSON.stringify({ ...action, action: action.type }) }));
    } catch (_error) {
      beloteStatus.textContent = "Cette action n’est plus disponible.";
      scheduleOnlinePoll(300);
    }
  };

  advanceBeloteBot = async function() {
    if (!beloteTable?.online) return soloAdvanceBeloteBot();
    await refreshOnlineState();
  };

  nextBeloteDeal = async function() {
    if (!beloteTable?.online) return soloNextBeloteDeal();

    try {
      renderOnlineState(await api("/api/belote-online/next-deal", { method: "POST", body: "{}" }));
    } catch (_error) {
      beloteStatus.textContent = "En attente que l’hôte démarre la donne suivante.";
    }
  };

  leaveBelote = async function() {
    if (!beloteTable?.online) return soloLeaveBelote();
    await leaveOnlineLobby();
  };

  renderBeloteActions = function() {
    if (beloteTable?.online && beloteTable.phase === "deal_finished" && !beloteTable.can_next_deal) {
      beloteActions.replaceChildren();
      const message = document.createElement("p");
      message.textContent = "En attente que l’hôte lance la donne suivante.";
      beloteActions.append(message);
      return;
    }

    soloRenderBeloteActions();
  };

  createButton.addEventListener("click", createOnlineLobby);
  joinButton.addEventListener("click", joinOnlineLobby);
  joinCode.addEventListener("keydown", (event) => { if (event.key === "Enter") joinOnlineLobby(); });
  startButton.addEventListener("click", startOnlineGame);
  leaveLobbyButton.addEventListener("click", leaveOnlineLobby);
});
