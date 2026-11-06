// Chaindance raster: a line-by-line port of App/Features/Ride/PixelCanvas.swift, RideVisualRaster.swift and RideVisualRider.swift.
// A procedural side view of a rainy night city, 192 × 60 (the Large view adds 36 rows of sky above), drawn back to front into an RGBA byte buffer.
// No DOM. Colours are packed 0xRRGGBB integers. Swift rounds halves away from zero and truncates integer division; `roundAway` and Math.trunc keep that.
// The scenery repeats exactly after LOOP_DISTANCE / LOOP_TIME, so nothing in it counts down to a ramp finish.
import { roundAway, RideVisualMotion, Posture, trailOf, showsSweat, showsSpeedLines, showsSparks, LOOP_TIME } from './state.mjs';

// ---- colours -------------------------------------------------------------------------------------------------------------------
export const ink = (r, g, b) => ((r & 255) << 16) | ((g & 255) << 8) | (b & 255);
const R_ = c => (c >> 16) & 255, G_ = c => (c >> 8) & 255, B_ = c => c & 255;
/** Linear mix towards another colour (0 keeps this one). */
export function mixed(a, b, amount) {
  const t = Math.max(0, Math.min(1, amount));
  const channel = (x, y) => Math.round(x + (y - x) * t);
  return ink(channel(R_(a), R_(b)), channel(G_(a), G_(b)), channel(B_(a), B_(b)));
}
const byte = value => Math.max(0, Math.min(255, Math.round(value * 255)));
const fromUnit = (r, g, b) => ink(byte(r), byte(g), byte(b));

/** The night palette. Zone colours are the dark-mode variants of the profile charts' zone palette (the bright ones). */
const ZONE_DARK = [fromUnit(0.53, 0.55, 0.53), fromUnit(0.13, 0.66, 0.58), fromUnit(0.28, 0.74, 0.28), fromUnit(0.59, 0.76, 0.17), fromUnit(1.00, 0.64, 0.90), fromUnit(1.00, 0.72, 0.96)];
export const Palette = Object.freeze({
  cyan: ink(0, 211, 224), magenta: ink(255, 0, 154), lime: ink(197, 247, 77), amber: ink(252, 184, 82), warmLight: ink(255, 205, 128), white: ink(236, 240, 250),
  zone: zone => (zone == null ? ink(0, 211, 224) : ZONE_DARK[zone]),
  teal: ZONE_DARK[1],
  accent: district => (district.kind === 'residential' ? ZONE_DARK[1] : district.zone == null ? ink(0, 211, 224) : ZONE_DARK[district.zone]),
});

// ---- deterministic hashing -------------------------------------------------------------------------------------------------------
const M64 = (1n << 64n) - 1n, C1 = 0x9E3779B97F4A7C15n, C2 = 0xC2B2AE3D27D4EB4Fn, C3 = 0xBF58476D1CE4E5B9n;
/** Deterministic, well-mixed integers for placing scenery without a random generator (UInt64 arithmetic, as Swift). */
export function pixelHash(a, b = 0) {
  let h = ((BigInt.asUintN(64, BigInt(a)) * C1) & M64) ^ ((BigInt.asUintN(64, BigInt(b)) * C2) & M64);
  h ^= h >> 29n; h = (h * C3) & M64; h ^= h >> 32n;
  return Number(h & 0x7fffffffn);
}

// ---- pixels ----------------------------------------------------------------------------------------------------------------------
const GLYPHS = {
  A: ['010', '101', '111', '101', '101'], B: ['110', '101', '110', '101', '110'], C: ['011', '100', '100', '100', '011'], D: ['110', '101', '101', '101', '110'], E: ['111', '100', '110', '100', '111'],
  F: ['111', '100', '110', '100', '100'], G: ['011', '100', '101', '101', '011'], H: ['101', '101', '111', '101', '101'], I: ['111', '010', '010', '010', '111'], J: ['001', '001', '001', '101', '010'],
  K: ['101', '101', '110', '101', '101'], L: ['100', '100', '100', '100', '111'], M: ['101', '111', '111', '101', '101'], N: ['110', '101', '101', '101', '101'], O: ['111', '101', '101', '101', '111'],
  P: ['110', '101', '110', '100', '100'], Q: ['010', '101', '101', '110', '011'], R: ['110', '101', '110', '101', '101'], S: ['011', '100', '010', '001', '110'], T: ['111', '010', '010', '010', '010'],
  U: ['101', '101', '101', '101', '111'], V: ['101', '101', '101', '101', '010'], W: ['101', '101', '111', '111', '101'], X: ['101', '101', '010', '101', '101'], Y: ['101', '101', '010', '010', '010'],
  Z: ['111', '001', '010', '100', '111'],
  0: ['111', '101', '101', '101', '111'], 1: ['010', '110', '010', '010', '111'], 2: ['110', '001', '010', '100', '111'], 3: ['110', '001', '010', '001', '110'], 4: ['101', '101', '111', '001', '001'],
  5: ['111', '100', '110', '001', '110'], 6: ['011', '100', '111', '101', '111'], 7: ['111', '001', '010', '010', '010'], 8: ['111', '101', '111', '101', '111'], 9: ['111', '101', '111', '001', '110'],
  '.': ['000', '000', '000', '000', '010'], ':': ['000', '010', '000', '010', '000'], '·': ['000', '000', '010', '000', '000'], '-': ['000', '000', '111', '000', '000'],
  '/': ['001', '001', '010', '100', '100'], '%': ['101', '001', '010', '100', '101'], '+': ['000', '010', '111', '010', '000'],
};
export const textWidth = text => Math.max(0, [...text].length * 4 - 1);

/** A small RGBA canvas drawn with integer coordinates. */
export class Pixels {
  constructor(width, height, background) {
    this.width = width; this.height = height; this.bytes = new Uint8ClampedArray(width * height * 4).fill(255);
    this.rect(0, 0, width, height, background);
  }
  ink(x, y) { if (x < 0 || y < 0 || x >= this.width || y >= this.height) return 0; const i = (y * this.width + x) * 4; return (this.bytes[i] << 16) | (this.bytes[i + 1] << 8) | this.bytes[i + 2]; }
  set(x, y, color) { if (x < 0 || y < 0 || x >= this.width || y >= this.height) return; const i = (y * this.width + x) * 4; this.bytes[i] = R_(color); this.bytes[i + 1] = G_(color); this.bytes[i + 2] = B_(color); }
  /** Draws a colour over what is there; `alpha` 1 replaces it. */
  blend(x, y, color, alpha) { if (!(alpha > 0)) return; if (alpha >= 1) { this.set(x, y, color); return; } this.set(x, y, mixed(this.ink(x, y), color, alpha)); }
  rect(x, y, w, h, color, alpha) {
    if (alpha === undefined) {
      const left = Math.max(0, x), right = Math.min(this.width, x + w), top = Math.max(0, y), bottom = Math.min(this.height, y + h);
      if (!(left < right) || !(top < bottom)) return;
      for (let row = top; row < bottom; row++) for (let col = left; col < right; col++) { const i = (row * this.width + col) * 4; this.bytes[i] = R_(color); this.bytes[i + 1] = G_(color); this.bytes[i + 2] = B_(color); }
    } else {
      if (!(w > 0) || !(h > 0)) return;
      for (let row = y; row < y + h; row++) for (let col = x; col < x + w; col++) this.blend(col, row, color, alpha);
    }
  }
  line(x1, y1, x2, y2, color, alpha = 1) {
    const steps = Math.max(Math.abs(x2 - x1), Math.abs(y2 - y1));
    if (steps === 0) { this.blend(x1, y1, color, alpha); return; }
    for (let step = 0; step <= steps; step++) { const t = step / steps; this.blend(x1 + roundAway((x2 - x1) * t), y1 + roundAway((y2 - y1) * t), color, alpha); }
  }
  /** A line drawn with a square brush, so limbs and tubes get a pixel-art thickness. */
  stroke(x1, y1, x2, y2, brush, color) {
    const steps = Math.max(Math.abs(x2 - x1), Math.abs(y2 - y1)), offset = Math.trunc((brush - 1) / 2);
    for (let step = 0; step <= Math.max(1, steps); step++) {
      const t = steps === 0 ? 0 : step / steps;
      const x = x1 + roundAway((x2 - x1) * t), y = y1 + roundAway((y2 - y1) * t);
      this.rect(x - offset, y - offset, brush, brush, color);
    }
  }
  polygon(points, color, alpha = 1) {
    const top = Math.max(0, Math.min(...points.map(p => p[1]))), bottom = Math.min(this.height - 1, Math.max(...points.map(p => p[1])));
    if (!(top <= bottom)) return;
    for (let y = top; y <= bottom; y++) {
      const xs = [];
      for (let index = 0; index < points.length; index++) {
        const a = points[index], b = points[(index + 1) % points.length];
        if ((a[1] <= y && b[1] > y) || (b[1] <= y && a[1] > y)) xs.push(a[0] + Math.trunc(((y - a[1]) * (b[0] - a[0])) / (b[1] - a[1])));
      }
      xs.sort((p, q) => p - q);
      for (let i = 0; i < xs.length - 1; i += 2) {
        if (alpha >= 1) this.rect(xs[i], y, xs[i + 1] - xs[i] + 1, 1, color);
        else for (let x = xs[i]; x <= xs[i + 1]; x++) this.blend(x, y, color, alpha);
      }
    }
  }
  /** A circle one pixel thick, symmetric about its centre pixel. */
  ring(cx, cy, radius, color) { for (let dy = -radius; dy <= radius; dy++) for (let dx = -radius; dx <= radius; dx++) if (Math.abs(Math.sqrt(dx * dx + dy * dy) - radius) <= 0.5) this.set(cx + dx, cy + dy, color); }
  disc(cx, cy, radius, color, alpha = 1) { for (let dy = -radius; dy <= radius; dy++) for (let dx = -radius; dx <= radius; dx++) if (dx * dx + dy * dy <= radius * radius + Math.trunc(radius / 2)) this.blend(cx + dx, cy + dy, color, alpha); }
  text(text, x, y, color, alpha = 1) {
    [...text.toUpperCase()].forEach((character, index) => {
      (GLYPHS[character] ?? []).forEach((bits, row) => { for (let col = 0; col < bits.length; col++) if (bits[col] === '1') this.blend(x + index * 4 + col, y + row, color, alpha); });
    });
  }
  clone() { const copy = Object.create(Pixels.prototype); copy.width = this.width; copy.height = this.height; copy.bytes = new Uint8ClampedArray(this.bytes); return copy; }
}

/** A drawing surface whose y axis starts `rowsAbove` rows below the top of the image, so negative y reaches the extra sky of the Large view. */
class Layer {
  constructor(width, height, rowsAbove, background) { this.base = new Pixels(width, height + rowsAbove, background); this.rowsAbove = rowsAbove; }
  get width() { return this.base.width; }
  /** Rows from y = 0 down: the strip itself. */
  get height() { return this.base.height - this.rowsAbove; }
  ink(x, y) { return this.base.ink(x, y + this.rowsAbove); }
  set(x, y, c) { this.base.set(x, y + this.rowsAbove, c); }
  blend(x, y, c, a) { this.base.blend(x, y + this.rowsAbove, c, a); }
  rect(x, y, w, h, c, a) { this.base.rect(x, y + this.rowsAbove, w, h, c, a); }
  line(x1, y1, x2, y2, c, a = 1) { this.base.line(x1, y1 + this.rowsAbove, x2, y2 + this.rowsAbove, c, a); }
  stroke(x1, y1, x2, y2, brush, c) { this.base.stroke(x1, y1 + this.rowsAbove, x2, y2 + this.rowsAbove, brush, c); }
  polygon(points, c, a = 1) { this.base.polygon(points.map(p => [p[0], p[1] + this.rowsAbove]), c, a); }
  ring(cx, cy, r, c) { this.base.ring(cx, cy + this.rowsAbove, r, c); }
  disc(cx, cy, r, c, a = 1) { this.base.disc(cx, cy + this.rowsAbove, r, c, a); }
  text(t, x, y, c, a = 1) { this.base.text(t, x, y + this.rowsAbove, c, a); }
  clone() { const copy = Object.create(Layer.prototype); copy.base = this.base.clone(); copy.rowsAbove = this.rowsAbove; return copy; }
}

// ---- skylines --------------------------------------------------------------------------------------------------------------------
/** A repeating row of buildings, stored per column so a frame can look up any column cheaply. */
class Skyline {
  constructor(period, seed, widths, heights) {
    this.period = period; this.height = new Array(period).fill(0); this.left = new Array(period).fill(0); this.width = new Array(period).fill(0); this.id = new Array(period).fill(0);
    let x = 0, n = 0;
    while (x < period) {
      let w = widths[0] + pixelHash(seed, n) % (widths[1] - widths[0] + 1);
      if (period - x - w < widths[0]) w = period - x;
      const h = heights[0] + pixelHash(seed, n + 977) % (heights[1] - heights[0] + 1);
      for (let column = x; column < x + w; column++) { this.height[column] = h; this.left[column] = x; this.width[column] = w; this.id[column] = n; }
      x += w; n += 1;
    }
  }
  /** Buildings that start in the period, for drawing signs once each. */
  get buildings() {
    const seen = new Set(), result = [];
    for (let column = 0; column < this.period; column++) if (!seen.has(this.id[column])) { seen.add(this.id[column]); result.push({ id: this.id[column], left: this.left[column], width: this.width[column], height: this.height[column] }); }
    return result;
  }
}

export const WIDTH = 192, HEIGHT = 60, HERO_HEIGHT = 96, RIDER_X = 64, ROAD_BASE = 51;
const far = new Skyline(192, 3, [9, 20], [8, 24]), mid = new Skyline(576, 5, [24, 46], [24, 42]), shops = new Skyline(960, 9, [18, 34], [9, 13]);
const WORDS = ['24H', 'WATT', 'FTP', 'SPIN', 'BAR', 'PUNK', 'ZONE', 'RAMP', 'W/KG', 'TUNE', 'NEON', 'GEAR'];

/**
 * Renders one frame. `scene`: { state, motion = new RideVisualMotion(), animated = true, highContrast = false, skyRows = 0 } where `state` is from rideVisualState.
 * `animated` false is Reduce Motion: no scrolling, parallax, rain or pedalling; pose, colour and signs still follow the state. `highContrast` outlines the rider.
 * Returns { width, height, data } (RGBA, alpha 255): 192 × 60, or 192 × 96 for the Large view (`skyRows` 36).
 */
export function renderRideVisual(scene) {
  const renderer = new Renderer(scene);
  renderer.scenery(); renderer.rider();
  const base = renderer.canvas.base;
  return { width: base.width, height: base.height, data: base.bytes };
}
/** Rows (from the top of the image) that the rider's drawing changes, found by drawing the same frame without it. */
export function riderRows(scene) {
  const withRider = renderRideVisual(scene), renderer = new Renderer(scene); renderer.scenery();
  const without = renderer.canvas.base.bytes;
  let first = null, last = 0;
  for (let y = 0; y < withRider.height; y++) for (let x = 0; x < withRider.width; x++) {
    const i = (y * withRider.width + x) * 4;
    if (withRider.data[i] !== without[i] || withRider.data[i + 1] !== without[i + 1] || withRider.data[i + 2] !== without[i + 2]) { first ??= y; last = y; }
  }
  return first == null ? null : [first, last + 1];
}
/** FNV-1a (64 bit) over a frame's bytes, as lowercase hex without leading zeros. Used by the parity fixture. */
export function fingerprint(bytes) {
  let hash = 0xcbf29ce484222325n;
  for (let i = 0; i < bytes.length; i++) hash = ((hash ^ BigInt(bytes[i])) * 0x100000001b3n) & M64;
  return hash.toString(16);
}

const mod = (value, period) => ((value % period) + period) % period;
const floorDiv = (value, size) => (value - mod(value, size)) / size;

class Renderer {
  constructor(scene) {
    this.scene = scene; this.state = scene.state; this.extra = scene.skyRows ?? 0; this.animated = scene.animated ?? true; this.highContrast = scene.highContrast ?? false;
    this.canvas = new Layer(WIDTH, HEIGHT, this.extra, ink(10, 10, 32));
    this.motion = this.animated ? (scene.motion ?? new RideVisualMotion()) : new RideVisualMotion();
    this.d = Math.floor(this.motion.distance);
    // Whole milliseconds, so a frame one loop later is exactly the same frame.
    this.time = (roundAway(this.motion.time * 1000) % Math.trunc(LOOP_TIME * 1000)) / 1000;
    const state = this.state;
    this.slope = state.world === 'skyway' ? 0.25 : state.world === 'descent' ? -0.25 : 0;
    // The skyline sinks as the rider climbs, with no end: it only slows down.
    const risen = 26 * (1 - Math.exp(-state.climbSeconds / 120));
    this.sink = state.world === 'boulevard' ? 0 : state.world === 'skyway' ? risen : state.world === 'descent' ? risen * (1 - state.descent) : risen * 0.5 + 12;
    this.reflections = [];
    const cyan = Palette.cyan, workout = state.mode === 'workout';
    this.columns = Array.from({ length: WIDTH }, (_, sx) => {
      if (!workout) return { accent: cyan, residential: false };
      const district = this.motion.districtAt(this.d + sx - RIDER_X) ?? state.district;
      return { accent: Palette.accent(district), residential: district.kind === 'residential' };
    });
  }
  get glow() { return this.state.glow; }
  roadTop(x) { return ROAD_BASE - Math.floor(this.slope * (x - RIDER_X)); }
  scenery() { this.sky(); this.heroSky(); this.farSkyline(); this.heroTowers(); this.spire(); this.midTowers(); this.shopfronts(); this.rail(); this.road(); this.markers(); this.signs(); this.rain(); }

  // ---- sky and skylines ----
  sky() {
    const c = this.canvas, extra = this.extra, d = this.d, top = ink(8, 8, 28), middle = ink(26, 16, 62), horizon = ink(78, 30, 104);
    for (let y = -extra; y < HEIGHT; y++) { const f = y / 50; c.rect(0, y, WIDTH, 1, f < 0.55 ? mixed(top, middle, f / 0.55) : mixed(middle, horizon, (f - 0.55) / 0.45)); }
    const haze = ink(110, 80, 170);
    for (let i = 0; i < 5; i++) {
      const x = mod(pixelHash(7, i) % 192 - Math.trunc(d / 8), 192), y = 3 + pixelHash(8, i) % 14, w = 26 + pixelHash(9, i) % 30;
      for (const shift of [-192, 0, 192]) { c.rect(x + shift, y, w, 2, haze, 0.13); c.rect(x + shift + 5, y - 1, w - 10, 1, haze, 0.1); }
    }
    if (this.state.world === 'rooftop') for (let y = 30; y < 52; y++) c.rect(0, y, WIDTH, 1, ink(255, 70, 190), 0.1 * (y - 30) / 22); // the city glows below the roof
  }
  /** Large view only: stars, a moon and the tips of a few very tall far towers in the extra sky above the strip. */
  heroSky() {
    const c = this.canvas, extra = this.extra; if (extra <= 0) return;
    for (let i = 0; i < 64; i++) {
      const x = pixelHash(i, 301) % WIDTH, y = -extra + pixelHash(i, 302) % (extra + 2);
      const twinkle = this.animated && (Math.trunc(this.time / 0.5) + i) % 6 === 0, bright = pixelHash(i, 303) % 4 === 0;
      c.blend(x, y, bright ? Palette.white : ink(150, 160, 215), twinkle ? 0.3 : bright ? 0.95 : 0.6);
    }
    const moon = ink(224, 228, 250), shade = ink(176, 182, 222);
    c.disc(150, -extra + 13, 12, moon, 0.1); c.disc(150, -extra + 13, 7, moon);
    c.disc(152, -extra + 11, 2, shade); c.disc(147, -extra + 16, 2, shade); c.set(153, -extra + 16, shade); c.set(146, -extra + 11, shade);
  }
  /** Large view only: slender far towers whose tips reach into the extra sky, with a slow red beacon. */
  heroTowers() {
    const c = this.canvas, extra = this.extra, d = this.d, time = this.time; if (extra <= 0) return;
    const base = 47 + Math.trunc(this.sink), body = ink(25, 21, 63), edge = ink(48, 40, 104), red = ink(255, 64, 84);
    [{ left: 22, width: 6, height: 62 }, { left: 88, width: 7, height: 74 }, { left: 146, width: 5, height: 56 }].forEach((tower, index) => {
      for (let sx = 0; sx < WIDTH; sx++) {
        const u = mod(sx + Math.trunc(d / 8), 192), lx = mod(u - tower.left, 192);
        if (!(lx < tower.width)) continue;
        const top = base - tower.height;
        for (let y = Math.max(-extra, top); y < Math.min(HEIGHT, base + 1); y++) {
          c.set(sx, y, y === top ? edge : lx === 0 ? mixed(edge, body, 0.5) : mixed(body, ink(70, 28, 100), (y - top) / tower.height * 0.5));
          const cell = pixelHash(index * 31 + lx, 500 + y);
          if (lx % 2 === 1 && (y - top) % 5 === 3 && cell % 4 === 0) c.blend(sx, y, Palette.warmLight, 0.6);
        }
        if (lx === Math.trunc(tower.width / 2)) {
          for (let y = Math.max(-extra, top - 6); y < top; y++) c.set(sx, y, edge);
          if (!this.animated || (Math.trunc(time / 0.75) + index) % 2 === 0) { c.set(sx, top - 7, red); c.blend(sx, top - 8, red, 0.35); }
        }
      }
    });
  }
  farSkyline() {
    const c = this.canvas, extra = this.extra, d = this.d, time = this.time, base = 47 + Math.trunc(this.sink), body = ink(25, 21, 63), edge = ink(48, 40, 104);
    for (let sx = 0; sx < WIDTH; sx++) {
      const u = mod(sx + Math.trunc(d / 8), 192), h = far.height[u], top = base - h;
      if (!(top < HEIGHT)) continue;
      const lx = u - far.left[u], index = far.id[u];
      for (let y = Math.max(-extra, top); y < Math.min(HEIGHT, base + 1); y++) {
        const depth = (y - top) / Math.max(1, h);
        c.set(sx, y, y === top ? edge : mixed(body, ink(70, 28, 100), depth * 0.5));
        const ly = y - top;
        if (!(lx % 3 === 1 && ly % 4 === 2 && ly > 1 && lx < far.width[u] - 1)) continue;
        const cell = pixelHash(index, Math.trunc(lx / 3) * 41 + Math.trunc(ly / 4));
        const lit = cell % 19 === 2 ? (Math.trunc(time / 1.5) + cell) % 2 === 0 : true;
        if (cell % 8 === 0 && lit) c.blend(sx, y, Palette.warmLight, 0.75);
        else if (cell % 8 === 1 && lit) c.blend(sx, y, Palette.cyan, 0.6);
      }
    }
    if (this.state.world === 'rooftop') { // a carpet of distant lights far below the roof
      for (let sx = 0; sx < WIDTH; sx++) for (let row = 0; row < 3; row++) {
        const cell = pixelHash(sx + Math.trunc(d / 8), 400 + row);
        if (cell % 5 === 0) c.blend(sx, 49 + row * 3, cell % 3 === 0 ? Palette.cyan : Palette.warmLight, 0.55);
      }
    }
  }

  // ---- the Spire ----
  spire() {
    const c = this.canvas, extra = this.extra, d = this.d, state = this.state, growth = state.spire;
    if (!(growth > 0) || state.world === 'rooftop') { this.rooftopMast(); return; }
    const left = WIDTH - Math.trunc(20 + 52 * growth), moving = state.world === 'skyway' || state.world === 'descent';
    const shiftU = moving ? Math.trunc(d * 3 / 8) : 0, shiftV = moving ? Math.trunc(d * 0.09375) : 0;
    const distant = 1 - growth, body = mixed(ink(20, 24, 66), ink(60, 30, 98), distant * 0.6), rib = mixed(ink(34, 40, 96), ink(70, 40, 112), distant * 0.6);
    for (let sx = Math.max(0, left); sx < WIDTH; sx++) {
      const u = sx + shiftU;
      for (let y = -extra; y < HEIGHT; y++) {
        const v = state.world === 'descent' ? y + shiftV : y - shiftV;
        let color = Math.trunc(u / 4) % 6 === 0 ? rib : body;
        if (mod(v, 24) < 2) color = mixed(rib, Palette.cyan, 0.35 * (1 - distant));
        c.set(sx, y, color);
        // Windows: 2 × 3 pixels on a 4 × 6 grid, hashed over a period that divides the road's loop.
        if (!(growth > 0.5 && mod(u, 4) >= 1 && mod(u, 4) <= 2 && mod(v, 6) >= 2 && mod(v, 6) <= 4 && mod(v, 24) > 2)) continue;
        const cell = pixelHash(mod(floorDiv(u, 4), 144), mod(floorDiv(v, 6), 24) + 61);
        if (cell % 3 === 0) c.blend(sx, y, cell % 9 === 0 ? Palette.magenta : cell % 9 === 3 ? Palette.cyan : Palette.warmLight, 0.7 * growth);
      }
    }
    // Neon edge down the side facing the rider, with a soft glow.
    if (left >= 0 && left < WIDTH) {
      c.rect(left, -extra, 1, HEIGHT + extra, Palette.magenta, 0.9); c.rect(left - 1, -extra, 1, HEIGHT + extra, Palette.magenta, 0.3);
      c.rect(left - 2, -extra, 1, HEIGHT + extra, Palette.magenta, 0.12); c.rect(left + 1, -extra, 1, HEIGHT + extra, Palette.magenta, 0.18);
    }
  }
  rooftopMast() {
    if (this.state.world !== 'rooftop') return;
    const c = this.canvas, mast = ink(60, 66, 120);
    c.rect(176, 8, 1, 43, mast); c.rect(175, 12, 3, 1, mast); c.rect(174, 20, 5, 1, mast);
    if (Math.trunc(this.time / 0.75) % 2 === 0) { c.set(176, 7, Palette.magenta); c.blend(176, 6, Palette.magenta, 0.4); }
  }

  // ---- mid towers and their neon ----
  midTowers() {
    const c = this.canvas, d = this.d, state = this.state, glow = this.glow, skyway = state.world !== 'boulevard';
    const base = 52 + Math.trunc(this.sink * (skyway ? 1.4 : 1)) + (state.world === 'rooftop' ? 10 : 0), body = ink(13, 12, 40);
    for (let sx = 0; sx < WIDTH; sx++) {
      const u = mod(sx + Math.trunc(d * 3 / 8), 576), h = mid.height[u], top = base - h;
      if (!(top < HEIGHT)) continue;
      const lx = u - mid.left[u], index = mid.id[u], column = this.columns[sx];
      for (let y = Math.max(0, top); y < Math.min(HEIGHT, base + 1); y++) {
        const ly = y - top;
        let color = body;
        if (ly === 0) color = ink(38, 33, 88);
        else if (lx === 0) color = mixed(column.accent, body, 0.6 + 0.3 * (1 - glow));
        else if (lx === mid.width[u] - 1) color = ink(8, 8, 26);
        c.set(sx, y, color);
        if (!(lx > 1 && lx < mid.width[u] - 2 && ly > 2 && mod(lx, 5) < 2 && mod(ly, 6) < 2)) continue;
        const cell = pixelHash(index, Math.trunc(lx / 5) * 53 + Math.trunc(ly / 6));
        if (cell % 4 === 0) {
          const accent = column.accent;
          const lamp = column.residential ? (cell % 8 === 0 ? Palette.warmLight : mixed(accent, ink(255, 230, 170), 0.4)) : (cell % 8 === 0 ? Palette.warmLight : accent);
          c.blend(sx, y, lamp, 0.55 + 0.35 * glow);
        }
      }
    }
    // Neon signs: one per building at most, once per visible repeat of the layer.
    for (const building of mid.buildings) {
      if (!(building.width >= 26 && pixelHash(building.id, 11) % 3 === 0)) continue;
      const word = WORDS[pixelHash(building.id, 12) % WORDS.length], w = textWidth(word) + 4;
      for (let repeatIndex = -1; repeatIndex <= 1; repeatIndex++) {
        const sx = building.left + repeatIndex * 576 - Math.trunc(d * 3 / 8) + Math.trunc((building.width - w) / 2);
        if (!(sx > -w && sx < WIDTH)) continue;
        const centre = Math.min(WIDTH - 1, Math.max(0, sx + Math.trunc(w / 2))), column = this.columns[centre];
        if (column.residential && pixelHash(building.id, 13) % 2 === 0) continue;
        const palette = [Palette.magenta, Palette.cyan, Palette.lime];
        const lamp = pixelHash(building.id, 14) % 2 === 0 ? column.accent : palette[pixelHash(building.id, 15) % palette.length];
        const y = base - building.height + 5 + pixelHash(building.id, 16) % 9;
        const dim = this.animated && pixelHash(building.id, 17) % 5 === 0 && this.time < 0.25; // a brief flicker, never under Reduce Motion
        this.neonBoard(sx, y, word, lamp, (dim ? 0.45 : 1) * (0.55 + 0.45 * glow));
        this.reflections.push({ x0: sx, x1: sx + w, ink: lamp, alpha: 0.2 });
      }
    }
  }
  /** Street-level shops behind the railing: awnings and lit windows in the district's colour, calmer in residential blocks. */
  shopfronts() {
    if (this.state.world !== 'boulevard') return;
    const c = this.canvas, d = this.d, glow = this.glow, base = 50, night = ink(11, 10, 34);
    for (let sx = 0; sx < WIDTH; sx++) {
      const u = mod(sx + Math.trunc(d * 5 / 8), 960), height = shops.height[u], top = base - height;
      const lx = u - shops.left[u], width = shops.width[u], index = shops.id[u];
      const column = this.columns[sx], strength = column.residential ? 0.5 : 0.6 + 0.4 * glow;
      if (!(lx > 0 && lx < width - 1)) { c.rect(sx, top, 1, height + 1, ink(6, 6, 22)); continue; }
      for (let y = top; y <= base; y++) {
        const ly = y - top;
        c.set(sx, y, ly === 0 ? ink(30, 28, 70) : night);
        if (ly === 1 || ly === 2) c.blend(sx, y, mixed(column.accent, night, Math.trunc(lx / 2) % 2 === 0 ? 0.2 : 0.55), strength);
        else if (ly >= 4 && ly <= height - 2 && lx >= 2 && lx < width - 2 && Math.abs(lx - Math.trunc(width / 2)) > 1 && pixelHash(index, 77) % 4 !== 0) {
          const warm = mixed(Palette.warmLight, column.accent, pixelHash(index, 78) % 3 === 0 ? 0.7 : 0.25);
          c.blend(sx, y, warm, 0.42 * strength);
        }
      }
    }
  }
  /** A framed neon word with a soft halo. */
  neonBoard(x, y, text, color, alpha = 1, h = 9) {
    const c = this.canvas, w = textWidth(text) + 4;
    c.rect(x - 1, y - 1, w + 2, h + 2, color, 0.2 * alpha);
    c.rect(x, y, w, h, ink(5, 5, 20));
    c.rect(x, y, w, 1, color, alpha); c.rect(x, y + h - 1, w, 1, color, alpha); c.rect(x, y, 1, h, color, alpha); c.rect(x + w - 1, y, 1, h, color, alpha);
    c.text(text, x + 2, y + Math.trunc((h - 5) / 2), mixed(color, ink(255, 255, 255), 0.35), alpha);
  }

  // ---- railing, lamps and road ----
  rail() {
    const c = this.canvas, d = this.d, glow = this.glow;
    for (let sx = 0; sx < WIDTH; sx++) {
      const top = this.roadTop(sx), column = this.columns[sx], post = mod(d + sx - RIDER_X, 8) === 0;
      c.set(sx, top - 8, mixed(ink(78, 90, 148), column.accent, 0.3 * glow));
      c.set(sx, top - 5, ink(44, 50, 100));
      if (post) for (let y = top - 7; y < top; y++) c.set(sx, y, ink(40, 46, 92));
    }
    // Lamp posts every 96 road pixels.
    const first = Math.floor((d - RIDER_X) / 96) - 1;
    for (let k = first; k <= first + 4; k++) {
      const x = RIDER_X + 40 + k * 96 - d;
      if (!(x > -8 && x < WIDTH + 8)) continue;
      const top = this.roadTop(x), headY = top - 27, column = this.columns[Math.min(WIDTH - 1, Math.max(0, x))];
      const light = mixed(Palette.warmLight, column.accent, 0.25);
      c.rect(x, headY, 1, 27, ink(62, 70, 118)); c.rect(x + 1, headY, 3, 1, ink(62, 70, 118)); c.rect(x + 2, headY + 1, 3, 1, light);
      c.disc(x + 3, headY + 2, 3, light, 0.2);
      c.polygon([[x + 2, headY + 2], [x + 4, headY + 2], [x + 11, top], [x - 5, top]], light, 0.07);
      this.reflections.push({ x0: x - 1, x1: x + 5, ink: light, alpha: 0.22 });
    }
  }
  road() {
    const c = this.canvas, d = this.d, glow = this.glow, state = this.state, deck = ink(26, 28, 56);
    for (let sx = 0; sx < WIDTH; sx++) {
      const top = this.roadTop(sx), column = this.columns[sx];
      if (!(top < HEIGHT)) continue;
      c.set(sx, top, mixed(column.accent, ink(20, 22, 44), 0.35 - 0.25 * glow));
      for (let y = top + 1; y < Math.min(HEIGHT, top + 8); y++) c.set(sx, y, mixed(deck, ink(14, 15, 34), (y - top) / 8));
      if (top + 8 < HEIGHT) for (let y = top + 8; y < Math.min(HEIGHT, top + 11); y++) c.set(sx, y, ink(34, 38, 78));
      if (top + 9 < HEIGHT && mod(d + sx - RIDER_X, 12) === 0) c.set(sx, top + 9, column.accent);
      if (mod(d + sx - RIDER_X, 24) < 10) c.blend(sx, top + 4, ink(170, 180, 220), 0.55); // lane dashes
    }
    // Wet reflections of the neon above and puddles that slide with the road.
    for (const item of this.reflections) {
      const low = Math.max(0, item.x0), high = Math.min(WIDTH, Math.max(item.x0 + 1, item.x1));
      if (!(low < high)) continue; // a lamp or sign just off either edge
      for (let sx = low; sx < high; sx++) { const top = this.roadTop(sx); for (let row = 2; row <= 6; row++) c.blend(sx, top + row, item.ink, item.alpha * (1 - (row - 2) / 6)); }
    }
    for (let k = -1; k <= 3; k++) {
      const base = Math.floor(d / 192) + k, x = RIDER_X + base * 192 + pixelHash(base % 8 + 8, 3) % 150 - d;
      if (!(x > -30 && x < WIDTH + 10)) continue;
      const top = this.roadTop(x + 8), w = 12 + pixelHash(base % 8 + 8, 4) % 12;
      c.rect(x, top + 5, w, 1, ink(110, 120, 190), 0.28); c.rect(x + 2, top + 6, w - 4, 1, ink(110, 120, 190), 0.16);
    }
    // Struts under the skyway.
    if (state.world === 'skyway' || state.world === 'descent') {
      for (let k = -1; k <= 4; k++) { const x = RIDER_X + 20 + k * 64 - mod(d, 64), top = this.roadTop(x) + 11; c.stroke(x, top, x - 12, top + 22, 2, ink(30, 34, 72)); }
    }
  }

  // ---- signs that pass the rider ----
  markers() {
    const c = this.canvas, d = this.d, state = this.state;
    for (const marker of this.motion.markers) {
      const sx = RIDER_X + Math.floor(marker.worldX) - d;
      if (!(sx > -90 && sx < WIDTH + 90)) continue;
      const top = this.roadTop(sx);
      if (marker.kind === 'level') { this.post(sx, top, top - 9); this.neonBoard(sx - Math.trunc(textWidth(marker.text) / 2) - 2, top - 18, marker.text, Palette.lime); }
      else if (marker.kind === 'gate') { this.post(sx, top, top - 11); this.neonBoard(sx - Math.trunc(textWidth(marker.text) / 2) - 2, top - 20, marker.text, Palette.cyan); }
      else if (marker.kind === 'billboard') {
        const accent = Palette.accent(this.motion.districtAt(marker.worldX + 40) ?? state.district), w = textWidth(marker.text) + 4, x = sx - Math.trunc(w / 2);
        this.post(x + 4, top, 14); this.post(x + w - 5, top, 14);
        this.neonBoard(x, 3, marker.text, accent, 1, 11);
      } else if (marker.kind === 'gantry') {
        const accent = Palette.accent(this.motion.districtAt(marker.worldX + 2) ?? state.district);
        c.rect(sx, top - 36, 2, 36, ink(62, 70, 118)); c.rect(sx - 10, top - 37, 22, 2, ink(62, 70, 118));
        for (let led = 0; led < 5; led++) c.set(sx - 8 + led * 4, top - 35, accent);
        for (let y = top - 34; y < top; y++) c.blend(sx + 3, y, accent, 0.1);
        c.rect(sx - 10, top - 37, 22, 1, accent, 0.35);
      }
    }
  }
  post(x, bottom, top) { if (!(bottom > top)) return; this.canvas.rect(x, top, 1, bottom - top, ink(58, 66, 112)); }
  /** Fixed signs: PAUSED, the finish sign on the rooftop, and the current level, step or gate under Reduce Motion. */
  signs() {
    const sign = this.state.sign, c = this.canvas; if (!sign) return;
    if (sign.kind === 'paused') {
      const w = textWidth(sign.text) + 4, x = 142 - Math.trunc(w / 2);
      c.line(x + 3, 0, x + 3, 4, ink(70, 78, 128)); c.line(x + w - 4, 0, x + w - 4, 4, ink(70, 78, 128));
      this.neonBoard(x, 5, sign.text, Palette.amber, 1, 11);
    } else if (sign.kind === 'finish') {
      const w = textWidth(sign.text) + 4, x = Math.min(WIDTH - w - 6, 138 - Math.trunc(w / 2) + 8);
      this.post(x + 5, ROAD_BASE, 22); this.post(x + w - 6, ROAD_BASE, 22);
      c.rect(x - 3, 5, w + 6, 19, Palette.magenta, 0.12);
      this.neonBoard(x, 8, sign.text, Palette.lime, 1, 13);
    } else {
      if (this.animated) return;
      this.neonBoard(150 - Math.trunc(textWidth(sign.text) / 2), 8, sign.text, sign.kind === 'level' ? Palette.lime : Palette.cyan);
    }
  }

  // ---- rain ----
  rain() {
    if (!this.animated) return;
    const c = this.canvas, slant = this.state.rainSlant * 0.8, phase = (this.time % 1.5) / 1.5;
    for (let i = 0; i < 44; i++) {
      const near = i < 26, span = HEIGHT + this.extra + 12;
      const x0 = pixelHash(i, 91) % (WIDTH + 40) - 20, y0 = pixelHash(i, 92) % span;
      const travel = (span * (near ? 2 : 1)) * phase;
      const y = (y0 + Math.trunc(travel)) % span - 6 - this.extra, x = x0 - Math.trunc(slant * y), length = near ? 3 : 2;
      c.line(x, y, x - roundAway(slant * length), y + length, ink(170, 192, 255), near ? 0.42 : 0.24);
    }
  }

  // ---- the rider ----
  /** The cyclist from the app icon, in profile and facing right. Every joint is placed in bike coordinates (x forward, y down, origin at the rear axle),
   *  tilted with the road, then drawn as pixel strokes, so the same code gives every posture and every pedal frame. */
  rider() {
    const c = this.canvas, state = this.state, time = this.time, animated = this.animated, motion = this.motion;
    const K = { frame: ink(56, 64, 114), frameLight: ink(104, 116, 178), tyre: ink(8, 10, 24), rim: Palette.cyan, spoke: ink(0, 104, 124), hub: ink(210, 220, 240),
      tights: ink(78, 86, 146), farTights: ink(36, 40, 78), shoe: ink(238, 242, 250), farShoe: ink(126, 132, 160), crank: ink(150, 158, 184), jacket: Palette.lime, jacketShade: ink(120, 170, 52),
      sleeve: ink(160, 214, 62), glove: ink(236, 240, 250), skin: ink(240, 192, 142), helmet: Palette.magenta, helmetShade: ink(150, 0, 92), helmetLight: ink(255, 128, 204), lens: ink(8, 8, 22), sweat: ink(160, 226, 255) };
    const zone = Palette.zone(state.zone), rearX = 53, angle = Math.atan(this.slope), rearY = this.roadTop(rearX) - 7, cosA = Math.cos(angle), sinA = Math.sin(angle);
    const p = (x, y) => ({ x: rearX + roundAway(x * cosA + y * sinA), y: rearY + roundAway(-x * sinA + y * cosA) });
    const power = state.zone == null ? 0.5 : [0.35, 0.5, 0.65, 0.8, 0.95, 1.0][state.zone];
    this.underglow(zone, power);
    { const lamp = p(23, -4), a = p(72, -2), b = p(72, 8); c.polygon([[lamp.x, lamp.y], [a.x, a.y], [b.x, b.y]], ink(255, 244, 205), 0.075); }
    this.trail(zone, p(-6, 0), this.slope);
    if (showsSpeedLines(state) && animated) this.speedLines(zone, rearY - 18);
    const before = this.highContrast ? c.clone() : null;

    // Posture. Joints are relative to the rear axle. Standing: hip raised and forward over the bottom bracket (12 px up; 13 would overreach the 17 px leg).
    const hip = state.posture === Posture.standing ? { x: 9, y: -12 } : { x: 5, y: -9 };
    let shoulderOffset, headOffset, handPosition;
    switch (state.posture) {
      case Posture.upright: [shoulderOffset, headOffset, handPosition] = [[2.5, -10.5], [1.5, -3], [16.5, -10.5]]; break;
      case Posture.hoods: [shoulderOffset, headOffset, handPosition] = [[6, -8.5], [3, -3], [19, -9.5]]; break;
      case Posture.low: [shoulderOffset, headOffset, handPosition] = [[8.8, -6], [3, -3], [20.5, -8]]; break;
      case Posture.drops: [shoulderOffset, headOffset, handPosition] = [[10.5, -3.5], [3, -3], [21.5, -6.5]]; break;
      default: [shoulderOffset, headOffset, handPosition] = [[8, -9], [3, -3], [20, -9.5]]; // standing: upright, hands on the hoods
    }
    const shoulder = { x: hip.x + shoulderOffset[0], y: hip.y + shoulderOffset[1] }, head = { x: shoulder.x + headOffset[0], y: shoulder.y + headOffset[1] };

    // Cranks: four frames a turn at the rider's real cadence; coasting holds them level.
    const frame = state.motion === 'pedalling' ? mod(Math.trunc(motion.crankTurns * 4), 4) : 0, bottomBracket = { x: 9, y: 1 };
    const pedal = quarter => { const a = quarter * Math.PI / 2; return { x: bottomBracket.x + 3.5 * Math.cos(a), y: bottomBracket.y + 3.5 * Math.sin(a) }; };
    const footDown = state.motion === 'footDown';
    const nearPedal = footDown ? { x: 8.5, y: 6 } : pedal(frame), farPedal = pedal(footDown ? 0 : frame + 2), crankPedal = pedal(footDown ? 2 : frame);

    const knee = foot => {
      const upper = 8.5, lower = 8.5, dx = foot.x - hip.x, dy = foot.y - hip.y;
      const distance = Math.min(upper + lower - 0.05, Math.max(0.5, Math.sqrt(dx * dx + dy * dy)));
      const a = distance / 2, h = Math.sqrt(Math.max(0, upper * upper - a * a)), ux = dx / distance, uy = dy / distance;
      let nx = -uy, ny = ux;
      if (nx * 1 + ny * -0.3 < 0) { nx = -nx; ny = -ny; } // knees point forward
      return { x: hip.x + ux * a + nx * h, y: hip.y + uy * a + ny * h };
    };
    const leg = (foot, thigh, shoe) => {
      const k = knee(foot), h = p(hip.x, hip.y), kn = p(k.x, k.y), f = p(foot.x, foot.y);
      c.stroke(h.x, h.y, kn.x, kn.y, 2, thigh); c.stroke(kn.x, kn.y, f.x, f.y, 2, thigh);
      c.rect(f.x - 1, f.y, 4, 1, shoe); c.rect(f.x, f.y - 1, 2, 1, shoe);
    };

    leg(farPedal, K.farTights, K.farShoe);
    const bb = p(bottomBracket.x, bottomBracket.y), far = p(farPedal.x, farPedal.y);
    c.line(bb.x, bb.y, far.x, far.y, K.crank, 0.7);
    this.bike(p, K);
    const headlight = p(22.5, -4), tail = p(2.5, -7);
    c.set(headlight.x, headlight.y, ink(255, 248, 214)); c.blend(headlight.x + 1, headlight.y, ink(255, 248, 214), 0.5);
    if (!animated || Math.trunc(time / 0.75) % 2 === 0) c.set(tail.x, tail.y, ink(255, 64, 84)); // blinks once every 1.5 s
    const near = p(crankPedal.x, crankPedal.y);
    c.line(bb.x, bb.y, near.x, near.y, K.crank);
    c.rect(bb.x - 1, bb.y - 1, 3, 3, K.crank);
    leg(nearPedal, K.tights, K.shoe);

    // Torso: shaded jacket with a stripe in the zone colour.
    const h = p(hip.x, hip.y), s = p(shoulder.x, shoulder.y), steep = Math.abs(s.y - h.y) > Math.abs(s.x - h.x), lift = steep ? [1, 0] : [0, -1];
    c.stroke(h.x, h.y, s.x, s.y, 3, K.jacketShade);
    c.stroke(h.x + lift[0], h.y + lift[1], s.x + lift[0], s.y + lift[1], 2, K.jacket);
    const mx = (h.x + s.x) / 2 + (s.x - h.x) * -0.05, my = (h.y + s.y) / 2 + (s.y - h.y) * -0.05;
    const length = Math.max(1, Math.sqrt((s.x - h.x) * (s.x - h.x) + (s.y - h.y) * (s.y - h.y)));
    const px = -(s.y - h.y) / length, py = (s.x - h.x) / length;
    for (let k = -1; k <= 1; k++) c.set(roundAway(mx + px * k), roundAway(my + py * k), zone);
    c.set(roundAway(mx + px * 2), roundAway(my + py * 2), mixed(zone, K.jacket, 0.5));

    // Arms to the bars, elbows bent more the lower the rider sits.
    const hand = p(handPosition[0], handPosition[1]);
    const elbow = { x: (shoulder.x + handPosition[0]) / 2 - 0.5, y: (shoulder.y + handPosition[1]) / 2 + (state.posture >= Posture.low && state.posture !== Posture.standing ? 2.2 : 1.4) };
    const e = p(elbow.x, elbow.y);
    c.stroke(s.x, s.y, e.x, e.y, 2, K.sleeve); c.stroke(e.x, e.y, hand.x, hand.y, 2, K.sleeve);
    c.rect(hand.x, hand.y, 2, 2, K.glove);

    // Head: skin, sunglasses and the magenta helmet.
    const hd = p(head.x, head.y);
    c.rect(hd.x, hd.y + 3, 2, 1, K.skin);
    c.rect(hd.x - 1, hd.y, 4, 1, K.skin); c.rect(hd.x, hd.y + 1, 3, 1, K.skin); c.rect(hd.x, hd.y + 2, 2, 1, K.skin);
    c.rect(hd.x + 1, hd.y, 2, 1, K.lens);
    c.set(hd.x + 2, hd.y, mixed(Palette.cyan, K.lens, 0.3));
    c.rect(hd.x - 1, hd.y - 3, 3, 1, K.helmet); c.rect(hd.x - 2, hd.y - 2, 5, 1, K.helmet); c.rect(hd.x - 3, hd.y - 1, 6, 1, K.helmet);
    c.set(hd.x, hd.y - 3, K.helmetLight); c.set(hd.x + 1, hd.y - 2, K.helmetLight);
    c.set(hd.x - 1, hd.y - 2, K.helmetShade); c.set(hd.x - 2, hd.y - 1, K.helmetShade); c.set(hd.x + 2, hd.y - 1, K.helmetShade);

    if (showsSweat(state)) this.sweat(hd, K);
    if (showsSparks(state) && animated) this.sparks(p(0, 6));
    if (before) this.outline(before);
  }
  bike(p, K) {
    const c = this.canvas, rear = p(0, 0), front = p(22, 0), bb = p(9, 1), seat = p(5, -8), head = p(19, -8), spokes = Math.trunc(this.d / 4) & 1;
    for (const centre of [rear, front]) this.wheel(centre.x, centre.y, spokes, K);
    c.line(bb.x, bb.y, rear.x, rear.y, K.frame); c.line(seat.x, seat.y, rear.x, rear.y, K.frame); c.line(bb.x, bb.y, seat.x, seat.y, K.frame);
    c.line(seat.x, seat.y, head.x, head.y, K.frameLight); c.line(head.x, head.y, bb.x, bb.y, K.frame); c.line(head.x, head.y, front.x, front.y, K.frame);
    // Saddle, stem and drop bars.
    const post = p(5, -9), saddleBack = p(2, -9.5), saddleFront = p(8, -9.5);
    c.line(seat.x, seat.y, post.x, post.y, K.frame); c.line(saddleBack.x, saddleBack.y, saddleFront.x, saddleFront.y, K.frameLight);
    const stem = p(18, -10), bar = p(21, -10), drop = p(22, -7);
    c.line(head.x, head.y, stem.x, stem.y, K.frame); c.line(stem.x, stem.y, bar.x, bar.y, K.frameLight); c.line(bar.x, bar.y, drop.x, drop.y, K.frameLight);
  }
  wheel(cx, cy, spokes, K) {
    const c = this.canvas;
    c.ring(cx, cy, 6, K.tyre); c.ring(cx, cy, 5, K.rim);
    if (spokes === 0) { c.line(cx - 4, cy, cx + 4, cy, K.spoke); c.line(cx, cy - 4, cx, cy + 4, K.spoke); }
    else { c.line(cx - 3, cy - 3, cx + 3, cy + 3, K.spoke); c.line(cx - 3, cy + 3, cx + 3, cy - 3, K.spoke); }
    c.set(cx, cy, K.hub);
  }
  /** Zone-coloured light under the bike, reflected a little in the wet road. */
  underglow(zone, strength) {
    const c = this.canvas, centre = 53 + 11, reach = 24;
    for (let dx = -reach; dx <= reach; dx++) {
      const x = centre + dx, top = this.roadTop(x), falloff = Math.pow(1 - Math.abs(dx) / (reach + 1), 2) * strength;
      c.blend(x, top - 1, zone, falloff * 0.3); c.blend(x, top, zone, falloff * 0.75); c.blend(x, top + 1, zone, falloff * 0.5); c.blend(x, top + 2, zone, falloff * 0.3); c.blend(x, top + 3, zone, falloff * 0.14);
    }
  }
  /** A light trail behind the rear wheel: longer and brighter the harder the effort. */
  trail(zone, start, tilt) {
    const c = this.canvas, spec = trailOf(this.state), length = spec.length;
    for (const [row, share] of [[-2, 0.55], [0, 1.0], [2, 0.8], [4, 0.4]]) {
      const rowLength = Math.trunc(length * share);
      if (!(rowLength > 0)) continue;
      for (let step = 0; step < rowLength; step++) {
        const fade = 1 - step / rowLength, y = start.y + row + roundAway(step * tilt);
        c.blend(start.x - step, y, zone, fade * (spec.dim ? 0.3 : 0.75));
      }
    }
  }
  speedLines(zone, y) {
    const c = this.canvas;
    for (let i = 0; i < 4; i++) {
      const speed = 1.2 + 0.3 * i, phase = (this.time / LOOP_TIME * speed * 3) % 1, length = 7 + (i % 3) * 3;
      const x = 44 - Math.trunc(phase * 44) - (i % 2) * 10, ly = y + i * 6 + (i % 2) * 2;
      c.line(x, ly, x - length, ly, mixed(Palette.white, zone, 0.4), 0.5 * (1 - phase));
    }
  }
  /** Two drops flying back from the head. */
  sweat(head, K) {
    const c = this.canvas;
    for (let i = 0; i < 2; i++) {
      const phase = this.animated ? (this.time / 0.6 + i * 0.5) % 1 : 0.15 + i * 0.5;
      const x = head.x - 3 - Math.trunc(phase * 5), y = head.y - 3 + Math.trunc(phase * 9);
      c.set(x, y, K.sweat); c.set(x, y + 1, K.sweat); c.blend(x, y - 1, K.sweat, 0.4);
    }
  }
  /** VO2max: sparks thrown off the rear tyre. They move; they never blink. */
  sparks(contact) {
    const c = this.canvas;
    for (let i = 0; i < 6; i++) {
      const phase = (this.time / 0.5 + i / 6) % 1, reach = 5 + (pixelHash(i, 5) % 9);
      const x = contact.x - 2 - Math.trunc(phase * reach), y = contact.y - Math.trunc(Math.sin(phase * Math.PI) * (2 + (pixelHash(i, 6) % 4)));
      c.blend(x, y, mixed(ink(255, 232, 140), ink(255, 110, 40), phase), 1 - phase * 0.6);
    }
  }
  /** Increase Contrast: a near-black outline around the body, and a thin light rim outside it so it shows on the night. */
  outline(before) {
    const c = this.canvas, width = c.width, height = c.height, rider = new Set();
    for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) if (c.ink(x, y) !== before.ink(x, y)) rider.add(y * width + x);
    const neighbours = index => {
      const x = index % width, y = Math.trunc(index / width);
      return [[x - 1, y], [x + 1, y], [x, y - 1], [x, y + 1]].filter(q => q[0] >= 0 && q[1] >= 0 && q[0] < width && q[1] < height).map(q => q[1] * width + q[0]);
    };
    const ring = new Set(), rim = new Set();
    for (const index of rider) for (const n of neighbours(index)) if (!rider.has(n)) ring.add(n);
    for (const index of ring) for (const n of neighbours(index)) if (!rider.has(n) && !ring.has(n)) rim.add(n);
    for (const index of rim) c.blend(index % width, Math.trunc(index / width), ink(244, 247, 255), 0.7);
    for (const index of ring) c.set(index % width, Math.trunc(index / width), ink(3, 3, 12));
  }
}
