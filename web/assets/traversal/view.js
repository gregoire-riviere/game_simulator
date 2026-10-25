import * as THREE from '/vendor/three.module.js';
import { OrbitControls } from '/vendor/OrbitControls.js';
import { generateBoard } from './generator.js';
import { pieceShape } from './pieces.js';

export function mountTraversal(page, api) {
  const host = page.querySelector('#traversal-canvas');
  const status = page.querySelector('#traversal-status');
  const seed = page.querySelector('#traversal-seed');
  const form = page.querySelector('#traversal-form');
  const fresh = page.querySelector('#traversal-new');
  const reset = page.querySelector('#traversal-reset');
  const top = page.querySelector('#traversal-top');
  const difficulty = page.querySelector('#traversal-difficulty');
  const selection = page.querySelector('#traversal-selection');
  const pieceOptions = page.querySelector('#traversal-pieces');
  const actionOptions = page.querySelector('#traversal-actions');
  const abort = new AbortController();
  let state = null, selected = null, busy = false, disposed = false, poll = null, generation = 0;
  let renderer;
  try {
    renderer = new THREE.WebGLRenderer({ antialias: true });
  } catch (_) {
    status.textContent = 'Le rendu 3D nécessite WebGL. Activez l’accélération graphique ou essayez un autre navigateur.';
    return () => {};
  }
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.setClearColor(0x101a2a);
  renderer.domElement.setAttribute('aria-label', 'Plateau de relief 3D : 10 lignes et 10 colonnes');
  host.replaceChildren(renderer.domElement);
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(40, 1, 0.1, 100);
  const controls = new OrbitControls(camera, renderer.domElement);
  controls.enablePan = false;
  controls.minDistance = 10;
  controls.maxDistance = 32;
  controls.maxPolarAngle = Math.PI / 2.05;
  controls.target.set(0, 1, 0);
  const render = () => renderer.render(scene, camera);
  controls.addEventListener('change', render);
  scene.add(new THREE.HemisphereLight(0xe6f5ff, 0x475569, 2.8));
  const light = new THREE.DirectionalLight(0xffffff, 3);
  light.position.set(-5, 12, 8);
  scene.add(light);
  let terrain = new THREE.Group();
  scene.add(terrain);

  function disposeGroup(group) {
    group.traverse(object => {
      object.geometry?.dispose();
      if (object.material) {
        object.material.map?.dispose();
        object.material.dispose();
      }
    });
  }

  function label(text, x, z) {
    const canvas = document.createElement('canvas');
    canvas.width = 64;
    canvas.height = 64;
    const context = canvas.getContext('2d');
    context.font = 'bold 38px sans-serif';
    context.textAlign = 'center';
    context.fillStyle = '#cbd5e1';
    context.fillText(text, 32, 47);
    const texture = new THREE.CanvasTexture(canvas);
    const sprite = new THREE.Sprite(new THREE.SpriteMaterial({ map: texture, depthTest: false }));
    sprite.position.set(x, 0.15, z);
    sprite.scale.set(0.45, 0.45, 1);
    terrain.add(sprite);
  }

  const targets = [];
  function rebuild() {
    scene.remove(terrain);
    disposeGroup(terrain);
    terrain = new THREE.Group();
    scene.add(terrain);
    const heights = state?.game?.board || generateBoard(seed.value);
    targets.length = 0;
    for (let z = 0; z < 10; z += 1) {
      for (let x = 0; x < 10; x += 1) {
        const height = heights[z][x];
        const thickness = 0.24 + height * 0.35;
        const color = new THREE.Color().setHSL(0.49 - height * 0.035, 0.22, 0.24 + height * 0.065 + (x + z) % 2 * 0.03);
        const tile = new THREE.Mesh(new THREE.BoxGeometry(0.96, thickness, 0.96), new THREE.MeshStandardMaterial({ color, roughness: 0.85 }));
        tile.position.set(x - 4.5, thickness / 2, z - 4.5);
        tile.userData = { row: z, col: x };
        targets.push(tile);
        terrain.add(tile);
        const playerPiece = state?.game?.pieces.find(p => p.status === 'active' && p.row === z && p.col === x);
        if (playerPiece) {
          const shape = pieceShape(playerPiece.type);
          const geometry = new THREE.BufferGeometry();
          // Flat faces keep the one/two/three upper vertices easy to read.
          geometry.setAttribute('position', new THREE.Float32BufferAttribute(shape.triangles.flatMap(face => face.flatMap(i => shape.vertices[i])), 3));
          geometry.computeVertexNormals();
          const piece = new THREE.Mesh(geometry, new THREE.MeshStandardMaterial({ color: playerPiece.id === selected ? 0xffe166 : playerPiece.player === 1 ? 0x8cbdff : 0xf3bb72, roughness: 0.35, metalness: 0.15 }));
          if (playerPiece.type === 'vanguard') piece.rotation.y = Math.PI / 4;
          piece.position.set(x - 4.5, thickness + 0.02, z - 4.5);
          piece.userData = { row: z, col: x, piece: playerPiece.id };
          targets.push(piece);
          terrain.add(piece);
        }
      }
      label(String(z + 1), -5.5, z - 4.5);
      label(String.fromCharCode(65 + z), z - 4.5, 5.5);
    }
    for (const move of (state?.legal || []).filter(m => m.piece === selected)) {
      const y = move.kind === 'exit' ? 0.25 : 0.28 + heights[move.row][move.col] * 0.35;
      const color = move.kind === 'attack' ? 0xfb7185 : move.kind === 'exit' ? 0x86efac : 0x7dd3fc;
      const marker = new THREE.Mesh(new THREE.RingGeometry(0.31, 0.43, move.kind === 'attack' ? 4 : 32), new THREE.MeshBasicMaterial({ color, side: THREE.DoubleSide, depthTest: false }));
      marker.rotation.x = -Math.PI / 2;
      marker.position.set(move.col - 4.5, y, move.row - 4.5);
      marker.renderOrder = 1;
      marker.userData = { row: move.row, col: move.col };
      targets.push(marker);
      terrain.add(marker);
    }
    updateStatus();
    // La table permet de vérifier les hauteurs exactes du rendu.
    const body = page.querySelector('#traversal-heights');
    body.replaceChildren();
    heights.forEach((row, z) => {
      const tr = document.createElement('tr');
      const header = document.createElement('th');
      header.scope = 'row';
      header.textContent = z + 1;
      tr.append(header);
      row.forEach(height => {
        const td = document.createElement('td');
        td.textContent = height;
        tr.append(td);
      });
      body.append(tr);
    });
    render();
  }

  function resetCamera() {
    camera.position.set(11, 13, 15);
    controls.target.set(0, 1, 0);
    controls.update();
    render();
  }
  function updateStatus() {
    const game = state?.game;
    const result = game?.result;
    const reasonNames = { first_sentinel: 'premier Sentinel sorti', two_exits: 'deux pièces sorties', no_active_pieces: 'un camp sans pièce active', move_limit_score: 'limite de 200 coups, score', move_limit_advancement: 'limite de 200 coups, progression puis force', threefold_repetition: 'répétition de séquence trois fois' };
    const difficulties = { easy: 'facile', medium: 'moyen', hard: 'difficile' };
    const outcome = result ? `${result.winner === 0 ? 'Match nul' : result.winner === 1 ? 'Vous avez gagné' : 'Le bot a gagné'} : ${reasonNames[result.reason]}.` : state?.blocked ? 'Aucun coup légal : partie bloquée. Vous pouvez lancer une nouvelle partie.' : busy || state?.thinking ? 'Le bot réfléchit…' : 'À vous de jouer — sélectionnez une pièce bleue.';
    status.textContent = game ? `${outcome} Score vous ${game.scores[0]} / bot ${game.scores[1]} · coup ${game.moves}/200 · bot ${difficulties[state.difficulty]}.` : 'Choisissez la difficulté, puis démarrez une nouvelle partie.';
    const piece = game?.pieces.find(p => p.id === selected);
    selection.textContent = piece ? `${piece.type} · ${String.fromCharCode(65 + piece.col)}${piece.row + 1} · ${piece.movement} PM · force ${piece.strength}.` : '';
    pieceOptions.replaceChildren();
    actionOptions.replaceChildren();
    for (const p of (game?.pieces || []).filter(p => p.player === 1 && p.status === 'active')) {
      const button = document.createElement('button');
      button.type = 'button'; button.textContent = `${p.type} ${String.fromCharCode(65 + p.col)}${p.row + 1}`;
      button.disabled = busy || state.thinking || Boolean(result) || game.turn !== 1;
      button.setAttribute('aria-pressed', String(p.id === selected));
      button.onclick = () => select(p.id);
      pieceOptions.append(button);
    }
    for (const move of (state?.legal || []).filter(m => m.piece === selected)) {
      const button = document.createElement('button');
      button.type = 'button'; button.className = `traversal-${move.kind}`;
      const names = { attack: 'Capturer', exit: 'Sortir', move: 'Aller' };
      button.textContent = `${names[move.kind]} ${String.fromCharCode(65 + move.col)}${move.kind === 'exit' ? ' hors plateau' : move.row + 1} · ${move.cost} PM${move.special ? ' (pouvoir)' : ''}${move.kind === 'attack' ? ` · ${move.attack} ≥ ${move.defence}` : ''}`;
      button.disabled = busy || state.thinking;
      button.onclick = () => play(move);
      actionOptions.append(button);
    }
    form.querySelector('button[type="submit"]').disabled = busy;
    fresh.disabled = busy;
  }

  function select(id) {
    if (busy || state?.thinking || state?.game?.result || state?.game?.turn !== 1) return;
    selected = selected === id ? null : id;
    rebuild();
  }

  async function refresh() {
    const version = generation;
    try {
      const next = await api('/api/traversal', { signal: abort.signal });
      if (disposed || version !== generation) return;
      state = next;
      selected = null;
      rebuild();
      if (state.thinking) poll = setTimeout(refresh, 250);
    } catch (error) {
      if (!disposed) { status.textContent = 'Chargement impossible. Rouvrez Traversal pour récupérer la partie.'; }
    }
  }

  async function play(move) {
    if (busy || !state || state.thinking || state.game.result) return;
    generation += 1;
    busy = true; updateStatus();
    try {
      const next = await api('/api/traversal/move', { method: 'POST', signal: abort.signal, body: JSON.stringify({ game_id: state.game_id, revision: state.revision, piece: move.piece, row: move.row, col: move.col }) });
      if (disposed) return;
      state = next; selected = null;
      if (state.thinking) poll = setTimeout(refresh, 200);
    } catch (error) {
      if (!disposed) { await refresh(); status.textContent = 'Action refusée ou connexion interrompue. État actualisé.'; }
    } finally {
      busy = false;
      if (!disposed) rebuild();
    }
  }

  async function newGame() {
    if (busy || disposed) return;
    clearTimeout(poll);
    generation += 1;
    busy = true; updateStatus();
    try {
      const next = await api('/api/traversal', { method: 'POST', signal: abort.signal, body: JSON.stringify({ board: generateBoard(seed.value), difficulty: difficulty.value }) });
      if (!disposed) { state = next; selected = null; }
    } catch (error) {
      if (!disposed) status.textContent = 'Impossible de créer la partie. Vérifiez votre connexion.';
    } finally {
      busy = false;
      if (!disposed) rebuild();
    }
  }
  const regenerate = event => { event.preventDefault(); newGame(); };
  const newSeed = () => { if (!busy) { seed.value = String(crypto.getRandomValues(new Uint32Array(1))[0]); newGame(); } };
  const raycaster = new THREE.Raycaster();
  let pointer = null;
  const down = event => { pointer = event.isPrimary ? { id: event.pointerId, x: event.clientX, y: event.clientY, moved: false } : null; };
  const motion = event => { if (pointer && Math.hypot(event.clientX - pointer.x, event.clientY - pointer.y) > 6) pointer.moved = true; };
  const cancel = () => { pointer = null; };
  const up = event => {
    const start = pointer; pointer = null;
    if (!start || start.id !== event.pointerId || start.moved || Math.hypot(event.clientX - start.x, event.clientY - start.y) > 6 || busy || state?.thinking) return;
    const rect = renderer.domElement.getBoundingClientRect();
    raycaster.setFromCamera(new THREE.Vector2((event.clientX - rect.left) / rect.width * 2 - 1, -(event.clientY - rect.top) / rect.height * 2 + 1), camera);
    const hit = raycaster.intersectObjects(targets)[0]?.object.userData;
    if (!hit) return;
    const piece = state?.game?.pieces.find(p => p.id === hit.piece);
    if (piece?.player === 1) { select(piece.id); return; }
    const move = state?.legal?.find(m => m.piece === selected && m.row === hit.row && m.col === hit.col);
    if (move) play(move);
  };
  renderer.domElement.addEventListener('pointerdown', down);
  renderer.domElement.addEventListener('pointermove', motion);
  renderer.domElement.addEventListener('pointercancel', cancel);
  renderer.domElement.addEventListener('pointerup', up);
  const topView = () => { camera.position.set(0, 23, 0.01); controls.target.set(0, 0, 0); controls.update(); render(); };
  const resize = () => {
    const width = host.clientWidth;
    const height = host.clientHeight;
    if (!width || !height) return;
    camera.aspect = width / height;
    camera.updateProjectionMatrix();
    renderer.setSize(width, height);
    render();
  };
  const observer = new ResizeObserver(resize);
  observer.observe(host);
  form.addEventListener('submit', regenerate);
  fresh.addEventListener('click', newSeed);
  reset.addEventListener('click', resetCamera);
  top.addEventListener('click', topView);
  resetCamera();
  rebuild();
  refresh();
  resize();
  return () => {
    disposed = true;
    abort.abort();
    clearTimeout(poll);
    pointer = null;
    renderer.domElement.removeEventListener('pointerdown', down);
    renderer.domElement.removeEventListener('pointermove', motion);
    renderer.domElement.removeEventListener('pointercancel', cancel);
    renderer.domElement.removeEventListener('pointerup', up);
    pieceOptions.replaceChildren();
    actionOptions.replaceChildren();
    observer.disconnect();
    form.removeEventListener('submit', regenerate);
    fresh.removeEventListener('click', newSeed);
    reset.removeEventListener('click', resetCamera);
    top.removeEventListener('click', topView);
    controls.dispose();
    disposeGroup(terrain);
    renderer.dispose();
    renderer.forceContextLoss();
    host.replaceChildren();
  };
}

