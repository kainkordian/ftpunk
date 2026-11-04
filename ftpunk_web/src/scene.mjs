// A small procedural pixel panorama. No remote fonts, images, or rendering libraries.
export function drawScene(canvas, { time = 0, phase = 'waiting', pedaling = false, dark = true, reducedMotion = false } = {}) {
  if (!canvas) return;
  const ctx = canvas.getContext('2d'), w = 384, h = 156;
  canvas.width = w; canvas.height = h; ctx.imageSmoothingEnabled = false;
  const t = reducedMotion ? 0 : time % 24, shift = Math.sin(t / 24 * Math.PI * 2), down = ['cooldown', 'completed'].includes(phase);
  const rect = (x, y, a, b, color) => { ctx.fillStyle = color; ctx.fillRect(Math.round(x), Math.round(y), Math.round(a), Math.round(b)); };
  const poly = (points, color) => { ctx.fillStyle = color; ctx.beginPath(); points.forEach(([x, y], i) => i ? ctx.lineTo(Math.round(x), Math.round(y)) : ctx.moveTo(Math.round(x), Math.round(y))); ctx.closePath(); ctx.fill(); };
  rect(0, 0, w, h, dark ? '#20343a' : '#a6d7db');
  rect(316, 17, 17, 17, '#f3ebac');
  for (const [x, y] of [[25, 23], [140, 14]]) { rect(x + shift * 4, y, 46, 5, '#e2e7cf'); rect(x + 10 + shift * 4, y - 4, 23, 5, '#e2e7cf'); }
  for (const [x, peak, width] of [[-25, 33, 160], [95, 16, 165], [239, 24, 175]]) {
    const p = x + width / 2 + shift * 2;
    poly([[x, 110], [p, peak], [x + width, 110]], dark ? '#607a7e' : '#789397');
    poly([[p, peak], [p - 18, peak + 26], [p - 3, peak + 20], [p + 9, peak + 29], [p + 19, peak + 26]], '#dfebdb');
  }
  poly([[0, 96], [53, 67], [115, 94], [191, 58], [267, 86], [341, 68], [384, 90], [384, h], [0, h]], dark ? '#385f50' : '#719b63');
  poly([[0, 128], [76, 103], [159, 116], [256, 94], [384, 119], [384, h], [0, h]], dark ? '#527348' : '#99b376');
  const bend = down ? -18 : shift * 23;
  poly([[170 + bend, 86], [194 + bend, 86], [278, h], [86, h]], '#b2b78a');
  poly([[175 + bend, 86], [190 + bend, 86], [264, h], [100, h]], '#555e5e');
  for (let y = 91; y < h; y += 14) { const depth = (y - 86) / 70; rect(182 + bend * (1 - depth), y + (pedaling ? time * 12 % 12 : 0), 2 + depth * 3, 5 + depth * 4, '#e5dfb5'); }
  for (const [x, y] of [[25, 104], [330, 112], [62, 127], [298, 97]]) { rect(x, y - 12, 3, 15, '#405346'); poly([[x - 6, y - 2], [x + 1, y - 24], [x + 8, y - 2]], '#254d41'); }
  const x = 184, y = 99 + (pedaling && !reducedMotion ? Math.floor(time * 3) % 2 : 0);
  rect(x - 3, y + 19, 7, 25, '#192b2a'); rect(x - 7, y + 18, 14, 3, '#6ce3d5');
  rect(x - 10, y + 9, 20, 15, '#c4f44b'); rect(x - 5, y + 10, 3, 12, '#86ad3d');
  rect(x - 11, y + 12, 3, 12, '#e3e7c7'); rect(x + 8, y + 12, 3, 12, '#e3e7c7');
  const pedal = pedaling && !reducedMotion ? Math.floor(time * 4) % 2 * 4 : 0;
  rect(x - 7, y + 24, 5, 10 - pedal, '#dee6cb'); rect(x + 3, y + 24, 5, 6 + pedal, '#dee6cb');
  rect(x - 4, y + 3, 9, 7, '#efdbbb'); rect(x - 7, y - 3, 15, 8, '#ff4f9a'); rect(x - 4, y - 6, 9, 4, '#ff4f9a');
  rect(x - 2, y - 2, 2, 6, '#623e62'); rect(x + 3, y - 2, 2, 6, '#623e62');
  rect(12, 12, 58, 14, '#172721'); ctx.fillStyle = '#c4f44b'; ctx.font = 'bold 8px monospace'; ctx.fillText(down ? 'DESCENT' : phase === 'ramp' ? 'STELVIO' : 'ROLL OUT', 18, 22);
}
export function drawChart(canvas, samples, { target = null } = {}) {
  if (!canvas) return;
  const box = canvas.getBoundingClientRect(), ratio = devicePixelRatio || 1;
  canvas.width = Math.round(Math.max(300, box.width) * ratio); canvas.height = Math.round(160 * ratio);
  const ctx = canvas.getContext('2d'); ctx.scale(ratio, ratio); const w = canvas.width / ratio, h = 160;
  const power = samples.filter(s => Number.isFinite(s.power)); const end = Math.max(60, samples.at(-1)?.time ?? 0), start = Math.max(0, end - 600);
  const visible = power.filter(s => s.time >= start), max = Math.max(200, target ?? 0, ...visible.map(s => s.power)) * 1.15;
  ctx.strokeStyle = '#7c897d40'; ctx.lineWidth = 1;
  for (let i = 1; i < 4; i++) { ctx.beginPath(); ctx.moveTo(0, h * i / 4); ctx.lineTo(w, h * i / 4); ctx.stroke(); }
  ctx.beginPath(); let previous = null;
  for (const s of visible) { const x = (s.time - start) / (end - start) * w, y = h - 8 - s.power / max * (h - 20); if (!previous || s.time - previous.time > 2) ctx.moveTo(x, y); else ctx.lineTo(x, y); previous = s; }
  ctx.lineWidth = 2; ctx.strokeStyle = '#83a82c'; ctx.stroke();
  if (target != null) { ctx.setLineDash([5, 5]); ctx.beginPath(); const y = h - 8 - target / max * (h - 20); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.strokeStyle = '#f169a0'; ctx.stroke(); }
}
