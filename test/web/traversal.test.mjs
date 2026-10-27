import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
// Import source as a module without changing the existing browser app's script mode.
const source = await readFile(new URL('../../web/assets/traversal/generator.js', import.meta.url), 'utf8');
const { generateBoard } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);

test('terrain is reproducible, including empty and Unicode seeds', () => {
  for (const seed of ['', 'traversal-001', 'été 🌋', '0', '123456789']) {
    assert.deepEqual(generateBoard(seed), generateBoard(seed));
  }
  assert.notDeepEqual(generateBoard('alpha'), generateBoard('beta'));
});

test('1000 seeds preserve dimensions, integer heights, fairness and traversable slopes', () => {
  for (let seed = 0; seed < 1000; seed += 1) {
    const board = generateBoard(String(seed));
    assert.equal(board.length, 10);
    board.forEach((row, z) => {
      assert.equal(row.length, 10);
      row.forEach((height, x) => {
        assert.ok(Number.isInteger(height) && height >= 0 && height <= 5);
        assert.equal(height, board[9 - z][9 - x]);
        // All eight neighbours, not only the four orthogonal directions.
        for (let dz = -1; dz <= 1; dz += 1) for (let dx = -1; dx <= 1; dx += 1) {
          if (board[z + dz]?.[x + dx] !== undefined) assert.ok(Math.abs(height - board[z + dz][x + dx]) <= 2);
        }
      });
    });
  }
});

test('seed population includes open plateaus, broken slopes and different relief amplitudes', () => {
  const layouts = new Set(), amplitudes = new Set();
  let open = 0, broken = 0, steep = 0, plateaus = 0;
  for (let seed = 0; seed < 1000; seed += 1) {
    const board = generateBoard(String(seed)), heights = board.flat();
    layouts.add(heights.join(','));
    amplitudes.add(Math.max(...heights) - Math.min(...heights));
    let equal = 0, edges = 0, hasSteep = false, hasPlateau = false;
    board.forEach((row, z) => row.forEach((height, x) => {
      for (const [dx, dz] of [[1, 0], [0, 1]]) {
        if (board[z + dz]?.[x + dx] === undefined) continue;
        const difference = Math.abs(height - board[z + dz][x + dx]);
        edges += 1;
        if (difference === 0) equal += 1;
        if (difference === 2) hasSteep = true;
      }
      if (height > 0 && height === row[x + 1] && height === board[z + 1]?.[x] && height === board[z + 1]?.[x + 1]) hasPlateau = true;
    }));
    // Wide margins guard variety without pinning exact seed snapshots or noise parameters.
    if (equal / edges > 0.7) open += 1;
    if (equal / edges < 0.5) broken += 1;
    if (hasSteep) steep += 1;
    if (hasPlateau) plateaus += 1;
  }
  assert.ok(layouts.size > 950, 'seeds should produce distinct layouts');
  assert.ok(amplitudes.size >= 3, 'relief should have several height ranges');
  assert.ok(open > 50 && broken > 50, 'include both open and more broken terrain');
  assert.ok(steep > 100, 'slopes should not always descend in single-step diamonds');
  assert.ok(plateaus > 500, 'elevated flat areas should be common');
});

test('vendor preparation produces self-hosted modules with the Three.js licence', async () => {
  const controls = await readFile(new URL('../../web/assets/vendor/OrbitControls.js', import.meta.url), 'utf8');
  assert.ok(controls.includes("from './three.module.js'"));
  assert.ok(!controls.includes("from 'three'"));
  const licence = await readFile(new URL('../../web/assets/vendor/THREE-LICENSE.txt', import.meta.url), 'utf8');
  assert.match(licence, /MIT License/);
});

const shapeSource = await readFile(new URL('../../web/assets/traversal/pieces.js', import.meta.url), 'utf8');
const { pieceShape } = await import(`data:text/javascript;base64,${Buffer.from(shapeSource).toString('base64')}`);

test('official silhouettes have pentagonal/quadrilateral/triangular bases and 1/2/3 upper vertices', () => {
  for (const [type, baseCount, tipCount] of [['explorer', 5, 1], ['vanguard', 4, 2], ['sentinel', 3, 3]]) {
    const { vertices, triangles } = pieceShape(type);
    assert.equal(vertices.filter(v => v[1] === 0).length, baseCount);
    const top = Math.max(...vertices.map(v => v[1]));
    assert.equal(vertices.filter(v => v[1] === top).length, tipCount);
    const centre = vertices.reduce((sum, v) => sum.map((x, i) => x + v[i] / vertices.length), [0, 0, 0]);
    const edges = new Map();
    for (const face of triangles) {
      assert.equal(new Set(face).size, 3);
      const [a, b, c] = face.map(i => vertices[i]);
      const u = b.map((x, i) => x - a[i]), v = c.map((x, i) => x - a[i]);
      const normal = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]];
      assert.ok(normal.reduce((sum, x, i) => sum + x * ((a[i] + b[i] + c[i]) / 3 - centre[i]), 0) > 0, `${type} faces must point outwards`);
      face.forEach((index, i) => {
        assert.ok(vertices[index]?.every(Number.isFinite));
        const edge = [index, face[(i + 1) % 3]].sort((a, b) => a - b).join(',');
        edges.set(edge, (edges.get(edge) || 0) + 1);
      });
    }
    assert.ok([...edges.values()].every(count => count === 2), `${type} must be a closed solid`);
  }
});

test('extended boards remain symmetric and traversable across seeds', () => {
  for (let seed = 0; seed < 100; seed += 1) {
    const board = generateBoard(String(seed), 12);
    assert.equal(board.length, 12);
    for (let r = 0; r < 12; r += 1) for (let c = 0; c < 12; c += 1) {
      assert.equal(board[r][c], board[11 - r][11 - c]);
      for (let dr = -1; dr <= 1; dr += 1) for (let dc = -1; dc <= 1; dc += 1) {
        if (board[r + dr]?.[c + dc] !== undefined) assert.ok(Math.abs(board[r][c] - board[r + dr][c + dc]) <= 2);
      }
    }
  }
});

test('cannon has its own closed geometry', () => {
  const shape = pieceShape('cannon');
  assert.equal(shape.vertices.length, 8);
  assert.equal(shape.triangles.length, 12);
});
