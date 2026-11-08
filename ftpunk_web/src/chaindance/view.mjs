// Chaindance view: draws the raster buffer into a <canvas> with `image-rendering: pixelated`, at most 12 frames a second.
// It animates only while the tab is visible, the visual is on screen, the ride is running, the debug stream is not paused and Reduce Motion is off;
// otherwise it redraws only when what it shows changes. It reads the ride and never sends a trainer command.
import { rideVisualState, rideVisualInput, RideVisualMotion, BRAND_NAME, HeroLayout, PLACEMENTS, placementTitle } from './state.mjs';
import { drawRiderSprite } from './rider-sprite.mjs';
import { renderRideVisual, WIDTH, HEIGHT, HERO_HEIGHT } from './raster.mjs';

export const FRAME_INTERVAL_MS = 1000 / 12;

/** Markup for the visual. `hero` adds the sky rows and the readout overlay that lives in them (filled by the cockpit). */
export function chaindanceHTML({ hero = false } = {}) {
  const height = hero ? HERO_HEIGHT : HEIGHT;
  return `<div class="chaindance ${hero ? 'hero' : 'strip'}" id="chaindance" data-testid="chaindance"><canvas id="chaindance-canvas" width="${WIDTH}" height="${height}" role="img" aria-label="${BRAND_NAME}"></canvas>${hero ? `<div class="chaindance-readout" id="chaindance-readout">
    <div class="readout-col"><p class="readout-title" id="readout-target-title">TARGET</p><p class="readout-value accent-text"><span id="readout-target">—</span><span class="readout-unit" id="readout-unit">W</span></p></div>
    <div class="readout-col"><p class="readout-title">ACTUAL</p><p class="readout-value"><span id="readout-actual">—</span><span class="readout-unit" id="readout-unit2">W</span></p></div>
    <p class="readout-detail" id="readout-detail"></p></div>` : ''}</div>`;
}
/** The placement menu. It sits in the cockpit header, outside the per-tick update path, so telemetry never rebuilds it (the native flicker bug of 2026-11-04). */
export const placementMenuHTML = placement => `<label class="placement-menu"><span class="sr-only">${BRAND_NAME} view</span><select id="chaindance-placement" aria-label="${BRAND_NAME} view" title="${BRAND_NAME} view: ${placementTitle(placement)}">${PLACEMENTS.map(([id, title]) => `<option value="${id}" ${id === placement ? 'selected' : ''}>${title}</option>`).join('')}</select></label>`;

/** Accumulates scroll distance, crank turns and announced signs between frames (RideVisualClock): plain bookkeeping of what has been drawn. */
export class RideVisualClock {
  constructor() { this.motion = new RideVisualMotion(); this.last = null; this.warmedUp = false; }
  /** Returns the scene for `state`. `now` is in seconds. Under Reduce Motion nothing accumulates. */
  scene(state, now, { animating, animated, highContrast, skyRows }) {
    if (!animated) return { state, animated: false, highContrast, skyRows };
    if (!this.warmedUp) { this.warmedUp = true; for (let i = 0; i < 40; i++) this.motion.advance(0.1, state); } // start a few seconds into the scenery, so signs already ahead are in view
    if (animating && this.last != null) this.motion.advance(now - this.last, state);
    this.last = now;
    return { state, motion: this.motion, animated: true, highContrast, skyRows };
  }
}

export class ChaindanceView {
  /** `root` is the element from `chaindanceHTML`; `source()` returns `{ engine, elapsed, playbackSpeed, mockPaused }` for the live ride. */
  constructor(root, source, { hero = false, now = () => performance.now() / 1000, env = globalThis } = {}) {
    Object.assign(this, { root, source, hero, now, env });
    this.canvas = root.querySelector('canvas'); this.ctx = this.canvas.getContext('2d'); this.clock = new RideVisualClock();
    this.onScreen = true; this.signature = null; this.label = null; this.state = null;
    const query = q => env.matchMedia?.(q) ?? { matches: false, addEventListener() {}, removeEventListener() {} };
    this.reduce = query('(prefers-reduced-motion: reduce)'); this.contrast = query('(prefers-contrast: more)');
    this.onPreference = () => { this.signature = null; this.frame(); };
    this.reduce.addEventListener?.('change', this.onPreference); this.contrast.addEventListener?.('change', this.onPreference);
    if (env.IntersectionObserver) { this.observer = new env.IntersectionObserver(entries => { this.onScreen = entries.at(-1)?.isIntersecting !== false; }); this.observer.observe(root); }
    this.timer = setInterval(() => this.frame(), FRAME_INTERVAL_MS); this.frame();
  }
  get animating() {
    const ride = this.source();
    return this.onScreen && !this.env.document?.hidden && !this.reduce.matches && !!ride.engine?.active && !ride.mockPaused;
  }
  /** One frame: reads the ride, redraws when animating or when what is shown changed. */
  frame() {
    if (!this.root.isConnected) { this.stop(); return; }
    const ride = this.source(), engine = ride.engine; if (!engine) return;
    const state = rideVisualState(rideVisualInput(engine, ride.elapsed, { playbackSpeed: ride.playbackSpeed ?? 1 })), animating = this.animating;
    this.state = state;
    if (state.accessibilitySummary !== this.label) { this.label = state.accessibilitySummary; this.canvas.setAttribute('aria-label', this.label); }
    const signature = `${state.world}/${state.zone}/${state.posture}/${state.motion}/${state.sign?.text}/${state.level}/${state.glow}/${Math.round(state.spire * 100)}/${Math.round(state.descent * 20)}/${state.district.kind}${state.district.zone}`;
    if (!animating && signature === this.signature) return;
    this.signature = signature;
    const frame = renderRideVisual({ ...this.clock.scene(state, this.now(), { animating, animated: !this.reduce.matches, highContrast: this.contrast.matches, skyRows: this.hero ? HeroLayout.skyRows : 0 }), sprite: drawRiderSprite });
    this.ctx.putImageData(new ImageData(frame.data, frame.width, frame.height), 0, 0);
  }
  stop() { clearInterval(this.timer); this.timer = null; this.observer?.disconnect(); this.reduce.removeEventListener?.('change', this.onPreference); this.contrast.removeEventListener?.('change', this.onPreference); }
}
