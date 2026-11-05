import { esc } from './components.mjs';
import { resultBands, bestMinuteBand, ResultChartLayout } from '../rules/presentation.mjs';
// SVG charts shared by the result screen, the activity detail and the Progress trend. Drawn in a fixed viewBox that scales as a whole,
// so text stays proportional. Colours come from CSS classes (light and dark pairs in base.css).
const num = n => Number(n.toFixed(1));

/** Recorded power with phase bands and the scored best minute highlighted and labelled. Labels sit in two rows inside the plot,
    each no wider than its own band (a band too narrow for the short form gets none; the accessible description names every phase). */
export function powerChart(session) {
  const W = 600, H = 220, left = 44, right = 10, top = 8, bottom = 30, plotW = W - left - right, plotH = H - top - bottom;
  const samples = session.samples.filter(s => Number.isFinite(s.power)), end = Math.max(60, session.endedAtOffset ?? session.samples.at(-1)?.time ?? 0);
  const peak = Math.max(0, ...samples.map(s => s.power)), ceiling = ResultChartLayout.ceiling(peak), minutes = end / 60;
  const x = seconds => left + (seconds / end) * plotW, y = watts => top + plotH - (watts / ceiling) * plotH;
  const bands = resultBands(session), best = bestMinuteBand(session);
  let svg = bands.map((b, i) => `<rect class="band band-${i % 2}" x="${num(x(b.start))}" y="${top}" width="${num(x(b.end) - x(b.start))}" height="${plotH}"/>`).join('');
  if (best) svg += `<rect class="best-window" x="${num(x(best.start))}" y="${top}" width="${num(x(best.end) - x(best.start))}" height="${plotH}"/>`;
  const step = ceiling > 600 ? 200 : ceiling > 300 ? 100 : 50;
  for (let w = 0; w <= ceiling; w += step) svg += `<line class="grid" x1="${left}" x2="${W - right}" y1="${num(y(w))}" y2="${num(y(w))}"/><text class="axis" x="${left - 6}" y="${num(y(w) + 4)}" text-anchor="end">${w}</text>`;
  const every = minutes > 60 ? 15 : minutes > 25 ? 5 : minutes > 10 ? 2 : 1;
  for (let m = 0; m <= minutes; m += every) svg += `<text class="axis" x="${num(x(m * 60))}" y="${H - 12}" text-anchor="middle">${m}</text>`;
  svg += `<text class="axis-title" x="${num(left + plotW / 2)}" y="${H - 1}" text-anchor="middle">Minutes</text><text class="axis-title" x="10" y="${top + 6}">W</text>`;
  // One polyline per continuous stretch: a gap of more than two seconds breaks the line.
  const lines = []; let current = [], previous = null;
  for (const s of samples) { if (previous && s.time - previous.time > 2) { lines.push(current); current = []; } current.push(`${num(x(s.time))},${num(y(s.power))}`); previous = s; }
  if (current.length) lines.push(current);
  svg += lines.filter(l => l.length > 1).map(l => `<polyline class="power-line" points="${l.join(' ')}"/>`).join('');
  for (const b of bands) { const label = ResultChartLayout.fittingLabel(b.title, x(b.end) - x(b.start) - 8, 6.4); if (label) svg += `<text class="band-label" x="${num(x(b.start) + 4)}" y="${top + 13}">${esc(label)}</text>`; }
  if (best) {
    const text = ResultChartLayout.fittingLabel(best.title, plotW - 8, 7.6);
    if (text) { const width = ResultChartLayout.estimatedWidth(text, 7.6) + 8, at = left + ResultChartLayout.clampedLeading((x(best.start) + x(best.end)) / 2 - left, width, plotW); svg += `<rect class="best-label-bg" x="${num(at)}" y="${top + 19}" width="${num(width)}" height="17" rx="4"/><text class="best-label" x="${num(at + 4)}" y="${top + 32}">${esc(text)}</text>`; }
  }
  const phases = bands.map(b => `${b.title} minute ${Math.floor(b.start / 60)} to ${Math.floor(b.end / 60)}`).join(', '), bestText = best ? `${best.title} between minute ${Math.floor(best.start / 60)} and ${Math.floor(best.end / 60)}` : '';
  const source = session.configuration.powerSource === 'trainer' ? 'Trainer' : 'External power meter';
  return `<svg class="power-chart" viewBox="0 0 ${W} ${H}" role="img" aria-label="Recorded power from ${source} over time. ${esc([phases, bestText].filter(Boolean).join('. '))}">${svg}</svg>`;
}

/** The FTP trend: one colour per rider (stable order), circles for real results and diamonds for debug results, and a legend that says so. */
export function trendChart(series, metric, { includeDebug = false } = {}) {
  const W = 600, H = 230, left = 48, right = 14, top = 12, bottom = 30, plotW = W - left - right, plotH = H - top - bottom;
  const points = series.flatMap(s => s.points); if (!points.length) return '';
  const values = points.map(p => p.value), times = points.map(p => p.time), decimals = metric === 'watts' ? 0 : 2;
  let lo = Math.min(...values), hi = Math.max(...values); const pad = Math.max((hi - lo) * 0.15, metric === 'watts' ? 10 : 0.2); lo = Math.max(0, lo - pad); hi += pad;
  const t0 = Math.min(...times), t1 = Math.max(...times, t0 + 86400000), x = t => left + ((t - t0) / (t1 - t0)) * plotW, y = v => top + plotH - ((v - lo) / (hi - lo)) * plotH;
  let svg = '';
  for (let i = 0; i <= 4; i++) { const v = lo + (hi - lo) * i / 4; svg += `<line class="grid" x1="${left}" x2="${W - right}" y1="${num(y(v))}" y2="${num(y(v))}"/><text class="axis" x="${left - 6}" y="${num(y(v) + 4)}" text-anchor="end">${v.toFixed(decimals)}</text>`; }
  for (let i = 0; i <= 3; i++) { const t = t0 + (t1 - t0) * i / 3; svg += `<text class="axis" x="${num(x(t))}" y="${H - 8}" text-anchor="${i === 0 ? 'start' : i === 3 ? 'end' : 'middle'}">${new Date(t).toLocaleDateString(undefined, { day: 'numeric', month: 'short' })}</text>`; }
  for (const s of series) {
    const line = s.points.map(p => `${num(x(p.time))},${num(y(p.value))}`).join(' ');
    svg += `<g class="series rider-${s.colorIndex % 6}">${s.points.length > 1 ? `<polyline class="trend-line" points="${line}"/>` : ''}${s.points.map(p => {
      const cx = num(x(p.time)), cy = num(y(p.value)), label = `${s.name}, ${p.debug ? 'debug' : 'real'}, ${new Date(p.time).toLocaleDateString(undefined, { dateStyle: 'medium' })}, ${p.value.toFixed(decimals)}`;
      return p.debug ? `<path class="point debug" d="M${cx} ${cy - 6} L${cx + 6} ${cy} L${cx} ${cy + 6} L${cx - 6} ${cy} Z"><title>${esc(label)}</title></path>` : `<circle class="point" cx="${cx}" cy="${cy}" r="5"><title>${esc(label)}</title></circle>`;
    }).join('')}</g>`;
  }
  const hasDebug = includeDebug && points.some(p => p.debug);
  const legend = `<ul class="legend" aria-label="Legend. Colour shows the rider. Circles are real results${hasDebug ? ', diamonds are debug results' : ''}.">${series.map(s => `<li class="rider-${s.colorIndex % 6}"><span class="dot" aria-hidden="true">●</span> ${esc(s.name)}</li>`).join('')}<li><span aria-hidden="true">○</span> Real result</li>${hasDebug ? '<li><span aria-hidden="true">◇</span> Debug result</li>' : ''}</ul>`;
  return `<div class="trend"><svg class="trend-chart" viewBox="0 0 ${W} ${H}" role="img" aria-label="${esc(metric === 'watts' ? 'FTP, W' : 'FTP, W/kg')} history by rider. Dated values are also in the activity list below.">${svg}</svg>${legend}</div>`;
}
