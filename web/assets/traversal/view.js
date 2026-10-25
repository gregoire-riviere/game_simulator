import * as THREE from '/vendor/three.module.js';
import { OrbitControls } from '/vendor/OrbitControls.js';
import { generateBoard } from './generator.js';

export function mountTraversal(page) {
  const host = page.querySelector('#traversal-canvas');
  const status = page.querySelector('#traversal-status');
  const seed = page.querySelector('#traversal-seed');
  const form = page.querySelector('#traversal-form');
  const fresh = page.querySelector('#traversal-new');
  const reset = page.querySelector('#traversal-reset');
  const top = page.querySelector('#traversal-top');
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

  function rebuild() {
    scene.remove(terrain);
    disposeGroup(terrain);
    terrain = new THREE.Group();
    scene.add(terrain);
    const heights = generateBoard(seed.value);
    for (let z = 0; z < 10; z += 1) {
      for (let x = 0; x < 10; x += 1) {
        const height = heights[z][x];
        const thickness = 0.24 + height * 0.35;
        const color = new THREE.Color().setHSL(0.49 - height * 0.035, 0.22, 0.24 + height * 0.065 + (x + z) % 2 * 0.03);
        const tile = new THREE.Mesh(new THREE.BoxGeometry(0.96, thickness, 0.96), new THREE.MeshStandardMaterial({ color, roughness: 0.85 }));
        tile.position.set(x - 4.5, thickness / 2, z - 4.5);
        terrain.add(tile);
        // Silhouettes de repérage uniquement ; aucune règle de jeu à cette étape.
        if ((z === 0 || z === 9) && x >= 2 && x <= 7) {
          const geometries = [() => new THREE.ConeGeometry(0.23, 0.65, 4), () => new THREE.SphereGeometry(0.24, 16, 12), () => new THREE.CylinderGeometry(0.19, 0.25, 0.55, 6)];
          const piece = new THREE.Mesh(geometries[[2, 1, 0, 0, 1, 2][x - 2]](), new THREE.MeshStandardMaterial({ color: z === 0 ? 0xf3bb72 : 0x8cbdff, roughness: 0.35, metalness: 0.15 }));
          piece.position.set(x - 4.5, thickness + 0.33, z - 4.5);
          terrain.add(piece);
        }
      }
      label(String(z + 1), -5.5, z - 4.5);
      label(String.fromCharCode(65 + z), z - 4.5, 5.5);
    }
    const maximum = Math.max(...heights.flat());
    status.textContent = `Graine : ${seed.value} · 100 cases · hauteurs 0–${maximum} · symétrie centrale · écart entre voisins ≤ 2`;
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
  const regenerate = event => { event.preventDefault(); rebuild(); };
  const newSeed = () => { seed.value = String(crypto.getRandomValues(new Uint32Array(1))[0]); rebuild(); };
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
  resize();
  return () => {
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
