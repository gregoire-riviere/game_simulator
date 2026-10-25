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
  const peaks = [];
  for (let i = 0; i < 4; i += 1) {
    const x = Math.floor(random() * BOARD_SIZE);
    const z = Math.floor(random() * BOARD_SIZE);
    const height = 2 + Math.floor(random() * 4);
    peaks.push({ x, z, height }, { x: 9 - x, z: 9 - z, height });
  }
  // Le maximum de cônes de pente 1 conserve un écart adjacent <= 1, donc <= 2.
  return Array.from({ length: BOARD_SIZE }, (_, z) =>
    Array.from({ length: BOARD_SIZE }, (_, x) =>
      Math.max(0, ...peaks.map(peak => peak.height - Math.abs(x - peak.x) - Math.abs(z - peak.z)))
    )
  );
}
