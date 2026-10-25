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

test('vendor preparation produces self-hosted modules with the Three.js licence', async () => {
  const controls = await readFile(new URL('../../web/assets/vendor/OrbitControls.js', import.meta.url), 'utf8');
  assert.ok(controls.includes("from './three.module.js'"));
  assert.ok(!controls.includes("from 'three'"));
  const licence = await readFile(new URL('../../web/assets/vendor/THREE-LICENSE.txt', import.meta.url), 'utf8');
  assert.match(licence, /MIT License/);
});
