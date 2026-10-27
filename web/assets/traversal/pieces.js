// Original geometry: the number of upper vertices matches the official strength.
function solid(vertices, triangles) {
  return { vertices, triangles: triangles.map(([a, b, c]) => [a, c, b]) };
}

export function pieceShape(type) {
  if (type === 'cannon') {
    return solid([[-0.25, 0, -0.2], [0.25, 0, -0.2], [0.25, 0, 0.2], [-0.25, 0, 0.2], [-0.18, 0.3, -0.16], [0.18, 0.3, -0.16], [0.18, 0.3, 0.16], [-0.18, 0.3, 0.16]], [[0, 2, 1], [0, 3, 2], [4, 5, 6], [4, 6, 7], [0, 1, 5], [0, 5, 4], [1, 2, 6], [1, 6, 5], [2, 3, 7], [2, 7, 6], [3, 0, 4], [3, 4, 7]]);
  }
  if (type === 'explorer') {
    const vertices = Array.from({ length: 5 }, (_, i) => [Math.cos(i * Math.PI * 2 / 5) * 0.27, 0, Math.sin(i * Math.PI * 2 / 5) * 0.27]);
    vertices.push([0, 0.65, 0]);
    return solid(vertices, [[0, 2, 1], [0, 3, 2], [0, 4, 3], ...vertices.slice(0, 5).map((_, i) => [i, (i + 1) % 5, 5])]);
  }
  if (type === 'vanguard') {
    return solid([[-0.27, 0, -0.22], [0.27, 0, -0.22], [0.27, 0, 0.22], [-0.27, 0, 0.22], [0, 0.6, -0.22], [0, 0.6, 0.22]], [[0, 2, 1], [0, 3, 2], [0, 1, 4], [3, 5, 2], [0, 4, 5], [0, 5, 3], [1, 2, 5], [1, 5, 4]]);
  }
  const vertices = [0, 1, 2].map(i => [Math.cos(i * Math.PI * 2 / 3) * 0.28, 0, Math.sin(i * Math.PI * 2 / 3) * 0.28]);
  vertices.push(...vertices.map(([x, , z]) => [x, 0.55, z]));
  return solid(vertices, [[0, 2, 1], [3, 4, 5], [0, 1, 4], [0, 4, 3], [1, 2, 5], [1, 5, 4], [2, 0, 3], [2, 3, 5]]);
}
