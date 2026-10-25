export const BOARD_SIZE = 10;

export function generateBoard(seed) {
  // FNV-1a puis un générateur entier : même graine, même relief sur chaque navigateur.
  let state = 2166136261;
  for (const character of String(seed)) {
    state = Math.imul(state ^ character.codePointAt(0), 16777619) >>> 0;
  }
  const random = () => {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return state / 4294967296;
  };
  // Deux grilles interpolées : grandes zones continues et détails plus locaux.
  const layer = spacing => {
    const size = Math.floor((BOARD_SIZE - 1) / spacing) + 2;
    const grid = Array.from({ length: size }, () => Array.from({ length: size }, random));
    const smooth = value => value * value * (3 - 2 * value);
    const mix = (a, b, amount) => a + (b - a) * amount;
    return (x, z) => {
      const gx = Math.floor(x / spacing), gz = Math.floor(z / spacing);
      const tx = smooth(x / spacing - gx), tz = smooth(z / spacing - gz);
      return mix(mix(grid[gz][gx], grid[gz][gx + 1], tx),
        mix(grid[gz + 1][gx], grid[gz + 1][gx + 1], tx), tz);
    };
  };
  const broad = layer(3.5 + random() * 3);
  const fine = layer(1.5 + random() * 1.5);
  const detail = 0.15 + random() * 0.35;
  const sample = (x, z) => broad(x, z) * (1 - detail) + fine(x, z) * detail;
  const field = Array.from({ length: BOARD_SIZE }, (_, z) =>
    Array.from({ length: BOARD_SIZE }, (_, x) => (sample(x, z) + sample(9 - x, 9 - z)) / 2));
  const minimum = Math.min(...field.flat()), maximum = Math.max(...field.flat());
  // L'amplitude varie aussi : ne pas forcer chaque carte à occuper les six niveaux.
  const amplitude = 2 + random() * 3;
  const base = random() * (5 - amplitude);
  let board = field.map(row => row.map(value => Math.round(base + (value - minimum) / (maximum - minimum || 1) * amplitude)));
  // Abaisser seulement les ruptures > 2, simultanément pour garder la symétrie.
  let changed;
  do {
    changed = false;
    board = board.map((row, z) => row.map((height, x) => {
      let limited = height;
      for (let dz = -1; dz <= 1; dz += 1) for (let dx = -1; dx <= 1; dx += 1) {
        if (board[z + dz]?.[x + dx] !== undefined) limited = Math.min(limited, board[z + dz][x + dx] + 2);
      }
      if (limited !== height) changed = true;
      return limited;
    }));
  } while (changed);
  return board;
}
