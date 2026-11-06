// The live power chart. (The ride visual, Chaindance, lives in src/chaindance/.)
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
