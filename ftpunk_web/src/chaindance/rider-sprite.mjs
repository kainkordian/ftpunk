// The Chaindance rider as a pixel sprite, from the RG SP design (ftpunk_rgsp mockup/riders.mjs): rider A "Sprinter" (short brown hair,
// classic road helmet, short sleeves) in rider D "Veteran" colours (violet jersey, yellow helmet, stripe and shorts, violet bike with yellow rims).
// SNES-RPG style: four-tone shading, coloured outlines, light from the top left. Sprite box 60 x 52; `p` only needs set(x, y, "#rrggbb").
// The app passes `drawRiderSprite` to the scene as `sprite`; scenes without it draw the original rider, which the pixel fixtures keep.

export const SW = 60, SH = 52;

/* ---------- shapes ---------- */
const key = (x, y) => (y << 8) | (x & 255);
class Shape {
  constructor() { this.m = new Set(); }
  disc(cx, cy, r) { const X = Math.round(cx), Y = Math.round(cy), R = Math.ceil(r);
    for (let y = -R; y <= R; y++) for (let x = -R; x <= R; x++) if (x * x + y * y <= r * r + r * .5) this.m.add(key(X + x, Y + y)); return this; }
  stroke(a, b, r0, r1 = r0) { const n = Math.max(Math.abs(b[0] - a[0]), Math.abs(b[1] - a[1]), 1) * 2;
    for (let k = 0; k <= n; k++) this.disc(a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n, r0 + (r1 - r0) * k / n); return this; }
  has(x, y) { return this.m.has(key(x, y)); }
  // Four tones: o outline, s shade, b base, l light.
  paint(p, T) {
    for (const k of this.m) { const x = k & 255, y = k >> 8, h = (dx, dy) => this.has(x + dx, y + dy);
      const c = !h(1, 0) || !h(-1, 0) || !h(0, 1) || !h(0, -1) ? T.o
        : !h(-1, -1) || !h(0, -2) || !h(-2, 0) ? T.l
        : !h(1, 1) || !h(0, 2) || !h(2, 0) ? T.s : T.b;
      p.set(x, y, c); }
  }
}
const far = T => ({ o: T.o, s: T.o, b: T.s, l: T.s });

const dot = (p, cx, cy, r, c) => { const X = Math.round(cx), Y = Math.round(cy), R = Math.ceil(r);
  for (let y = -R; y <= R; y++) for (let x = -R; x <= R; x++) if (x * x + y * y <= r * r + r * .5) p.set(X + x, Y + y, c); };
const line = (p, a, b, c) => { const n = Math.max(Math.abs(b[0] - a[0]), Math.abs(b[1] - a[1]), 1);
  for (let k = 0; k <= n; k++) p.set(Math.round(a[0] + (b[0] - a[0]) * k / n), Math.round(a[1] + (b[1] - a[1]) * k / n), c); };
const ring = (p, cx, cy, r0, r1, c, arc) => { const R = Math.ceil(r1) + 1;
  for (let y = -R; y <= R; y++) for (let x = -R; x <= R; x++) { const d = Math.hypot(x, y); if (d >= r0 && d < r1 && (!arc || arc(Math.atan2(y, x)))) p.set(cx + x, cy + y, c); } };
const stamp = (p, rows, pal, ox, oy) => rows.forEach((row, y) => { for (let x = 0; x < row.length; x++) { const c = pal[row[x]]; if (c) p.set(ox + x, oy + y, c); } });
const joint = (a, b, l1, l2, mode = 'forward') => { const dx = b[0] - a[0], dy = b[1] - a[1], d = Math.min(Math.hypot(dx, dy), l1 + l2 - .01);
  const q = Math.atan2(dy, dx), w = Math.acos((l1 * l1 + d * d - l2 * l2) / (2 * l1 * d));
  const k1 = [a[0] + Math.cos(q - w) * l1, a[1] + Math.sin(q - w) * l1], k2 = [a[0] + Math.cos(q + w) * l1, a[1] + Math.sin(q + w) * l1];
  return mode === 'down' ? (k1[1] > k2[1] ? k1 : k2) : (k1[0] > k2[0] ? k1 : k2); };

/* ---------- tones (o outline, s shade, b base, l light) ---------- */
const SKIN = { o: '#7a3a24', s: '#d08860', b: '#f6c09a', l: '#ffe2c8' };
const METAL = { o: '#1a1630', s: '#4a4580', b: '#8a86b8', l: '#d8dcec' };
const DARK = { o: '#0e0a1e', s: '#1c1838', b: '#2c2650', l: '#4a4580' };
const VIOLET = { o: '#1e0a40', s: '#4a2a9a', b: '#7a4ae0', l: '#b89cff' };
const YELLOW = { o: '#4a3a00', s: '#b09000', b: '#f5d020', l: '#fff3a0' };
const skinPal = T => ({ k: T.o, S: T.s, s: T.b, L: T.l, e: '#20101a', w: '#ffffff' });

/* ---------- head: one letter per palette colour ---------- */
// Everyone but the squirrel wears the same classic road helmet (o D H h V, in their own colours) over a face
// (hair at the nape r R q, skin k S s L, eye e w, chin strap t). Riders differ by overlays on the face.
const HELMET = [
  '.......oooooo.....',
  '.....ooHHhhhhHoo..',
  '....oHHVHHhVhHHHo.',
  '...oHHVHHHVHHHVHHo',
  '..oDHHHHHHHHHHHHHo',
  '..oDDHVHHHHVHHHHDo',
  '..oDDDDDDDDDDDDDo.',
];
const FACE = [
  '..rRRqRktsLLLLLsk.',
  '..rRRRkSktssswesk.',
  '..rrRRkkstssseesk.',
  '...rrRksstsssssssk',
  '...rrkSssstsssssk.',
  '....rkSSsstssssk..',
  '.....kkSSSSSSkk...',
  '.......kkkkkk.....',
];
// overlay: [row, column, text] on the face rows ('.' in the text keeps what is there)
const face = (...over) => { const rows = FACE.slice();
  for (const [r, c, txt] of over) { if (r >= rows.length) rows.push('.'.repeat(18)); const a = [...rows[r]]; [...txt].forEach((ch, i) => { if (ch !== '.') a[c + i] = ch; }); rows[r] = a.join(''); }
  return [...HELMET, ...rows]; };
const SPRINTER_HEAD = face();
const helmetPal = T => ({ o: T.o, D: T.s, H: T.b, h: T.l, V: T.o, t: T.o });

const ROAD = { rw: [18, 41], fw: [47, 41], r: 9, bb: [30, 41], crank: 4, seat: [25, 28], ht: [43, 28], hip: [26, 27], l: 10, shoulder: [37, 19], bars: [48, 27], head: [31, 4], drops: true };
const wheelOf = (rim, hub) => ({ fat: false, tyre: '#1c1838', tyreHi: '#4a4580', rim, spoke: '#6a6590', hub, out: '#0e0a1e' });

/** Rider A's build (head, bare arms, shoes) in rider D's colours. */
export const RIDER = {
  geo: ROAD,
  head: { rows: SPRINTER_HEAD, pal: { ...helmetPal(YELLOW), ...skinPal(SKIN), r: '#3a1c0c', R: '#7a4220', q: '#b06a34' } },
  torso: VIOLET, stripe: YELLOW.b, shorts: YELLOW, shin: SKIN, sock: '#ffffff', shoe: DARK,
  sleeve: VIOLET, forearm: SKIN, glove: DARK, frame: VIOLET, saddle: DARK, wheel: wheelOf(YELLOW.b, YELLOW.l),
};

/* ---------- wheels ---------- */
const topLeft = q => q < -Math.PI * .45 && q > -Math.PI * .95;
function wheel(p, c, r, spin, W) {
  const [x, y] = c, n = W.fat ? 3 : 4, tyreIn = W.fat ? r - 2.5 : r - 1.5;
  for (let k = 0; k < n; k++) { const q = spin + k * Math.PI / n; line(p, [x - Math.cos(q) * (tyreIn - 1), y - Math.sin(q) * (tyreIn - 1)], [x + Math.cos(q) * (tyreIn - 1), y + Math.sin(q) * (tyreIn - 1)], W.spoke); }
  ring(p, x, y, tyreIn - 1, tyreIn, W.rim);
  ring(p, x, y, tyreIn, r + .5, W.tyre);
  ring(p, x, y, r - .5, r + .5, W.tyreHi, topLeft);
  if (W.fat) ring(p, x, y, r - .5, r + .5, W.out, q => Math.round((q + Math.PI) * 4 + spin * 4) % 2 === 0 && !topLeft(q));
  ring(p, x, y, r + .5, r + 1.5, W.out);
  dot(p, x, y, 1.5, W.out); p.set(x, y, W.hub);
}

/* ---------- one frame ---------- */
export function drawRider(p, R, t) {
  const G = R.geo, theta = t * Math.PI * 2 * 1.4, spin = t * 9;
  const bob = Math.sin(theta * 2) > .2 ? 1 : 0;
  const pedal = phase => [G.bb[0] + Math.cos(theta + phase) * G.crank, G.bb[1] + Math.sin(theta + phase) * G.crank];
  const hip = G.hip, sh = [G.shoulder[0], G.shoulder[1] + bob];
  const leg = (phase, near) => {
    const f = pedal(phase), k = joint(hip, f, G.l, G.l), ankle = [f[0] - .5, f[1] - 1.5];
    const tone = T => near ? T : far(T);
    new Shape().stroke(k, ankle, 2, 1.5).paint(p, tone(R.shin));
    if (R.sock) line(p, [ankle[0] - 1, ankle[1]], [ankle[0] + 1, ankle[1]], near ? R.sock : '#6a6590');
    const thigh = new Shape().stroke(hip, k, 2.7, 2);
    thigh.paint(p, tone(R.shorts));
    if (R.kneePads) new Shape().disc(k[0], k[1], 2).stroke(k, [k[0] + (ankle[0] - k[0]) * .18, k[1] + (ankle[1] - k[1]) * .18], 2).paint(p, tone(R.kneePads));
    new Shape().stroke([f[0] - 2, f[1]], [f[0] + 2.5, f[1]], 1.5).paint(p, tone(R.shoe));
  };
  // far side
  leg(Math.PI, false);
  // bike
  wheel(p, G.rw, G.r, spin, R.wheel); wheel(p, G.fw, G.r, spin, R.wheel);
  const frame = new Shape(), T = (a, b) => frame.stroke(a, b, 1);
  T(G.rw, G.bb); T(G.rw, G.seat); T(G.bb, G.seat); T(G.seat, G.ht); T(G.bb, G.ht); T(G.ht, G.fw);
  const crown = [G.ht[0] + (G.fw[0] - G.ht[0]) * .45, G.ht[1] + (G.fw[1] - G.ht[1]) * .45];
  const stemTop = [G.ht[0] + 1, G.bars[1] + 1]; T(G.ht, stemTop);
  frame.paint(p, { ...R.frame, l: R.frame.b });
  if (G.suspension) { new Shape().stroke(G.ht, crown, 1).paint(p, { ...METAL, l: METAL.l, b: METAL.l }); new Shape().stroke(crown, [G.fw[0] - .5, G.fw[1] - 1], 2).paint(p, DARK); } // stanchions, lowers
  const bars = new Shape().stroke(stemTop, [G.bars[0] + 1, G.bars[1]], 1);
  if (G.drops) bars.stroke([G.bars[0] + 1, G.bars[1]], [G.bars[0] + 2, G.bars[1] + 3], 1);
  bars.paint(p, METAL);
  if (G.plate) { for (let y = -1; y <= 4; y++) for (let x = -1; x <= 4; x++) p.set(G.ht[0] + 1 + x, G.ht[1] - 2 + y, (x < 0 || x > 3 || y < 0 || y > 3) ? '#2a3a08' : G.plate);
    p.set(G.ht[0] + 2, G.ht[1] - 1, '#2a3a08'); p.set(G.ht[0] + 3, G.ht[1] - 1, '#2a3a08'); }
  new Shape().stroke([G.seat[0] - 3, G.seat[1] - 1], [G.seat[0] + 2, G.seat[1] - 1], 1).paint(p, R.saddle);
  new Shape().disc(G.bb[0], G.bb[1], 2.5).paint(p, METAL);
  // rider
  R.behind?.(p, R, t, bob);
  const torso = new Shape().stroke(hip, sh, 2.7, 3.5).disc(sh[0] - 1, sh[1] + 1, 3.5);
  torso.paint(p, R.torso);
  if (R.stripe) line(p, [hip[0] + 1, hip[1] - 1], [sh[0], sh[1] + 2], R.stripe);
  const hands = G.bars, elbow = joint(sh, hands, 7.5, 7.5, 'down');
  // bare arm from mid upper arm to the hand, then the short sleeve over the top (long sleeves: R.longSleeves)
  const cuff = R.longSleeves ? elbow : [sh[0] + (elbow[0] - sh[0]) * .5, sh[1] + (elbow[1] - sh[1]) * .5];
  new Shape().stroke(cuff, elbow, 2).stroke(elbow, hands, 2, 1.5).paint(p, R.longSleeves ? R.sleeve : R.forearm);
  new Shape().stroke(sh, cuff, 2.7, 2.2).paint(p, R.sleeve);
  new Shape().disc(hands[0], hands[1], 2).paint(p, R.glove);
  stamp(p, R.head.rows, R.head.pal, G.head[0], G.head[1] + bob);
  R.face?.(p, R, G.head[0], G.head[1] + bob, t);
  line(p, G.bb, pedal(0), METAL.s); dot(p, G.bb[0], G.bb[1], .5, METAL.l);
  leg(0, true);
}

/** The hook `renderRideVisual` calls: draws the sprite with its rear wheel on the road under the scene's rear axle. */
export function drawRiderSprite(set, rear, roadY, time) {
  const G = RIDER.geo, ox = rear.x - G.rw[0], oy = roadY - G.r - 2 - G.rw[1];
  drawRider({ set: (x, y, c) => set(Math.round(ox + x), Math.round(oy + y), c) }, RIDER, time);
}
