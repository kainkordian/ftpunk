import { esc } from './components.mjs';
import { resultBands, bestMinuteBand, ResultChartLayout, DurationFormat } from '../rules/presentation.mjs';
import { rideSummary, targetSeries, rideMoment } from '../rules/ride-summary.mjs';
import { heartRateVariability } from '../rules/hrv.mjs';
import { rideBalance, balanceSeries, balanceAxisReach } from '../rules/virtual-ride.mjs';
// SVG charts shared by the result screen, the activity detail and the Progress trend. Drawn in a fixed viewBox that scales as a whole,
// so text stays proportional. Colours come from CSS classes (light and dark pairs in base.css).
const num = n => Number(n.toFixed(1));

/** Recorded power with phase bands and the scored best minute highlighted and labelled. Labels sit in two rows inside the plot,
    each no wider than its own band (a band too narrow for the short form gets none; the accessible description names every phase). */
export function powerChart(session) {
  const W = 600, H = 220, left = 44, right = 10, top = 8, bottom = 30, plotW = W - left - right, plotH = H - top - bottom;
  const samples = session.samples.filter(s => Number.isFinite(s.power)), end = Math.max(60, session.endedAtOffset ?? session.samples.at(-1)?.time ?? 0);
  const targets = targetSeries(session), peak = Math.max(0, ...samples.map(s => s.power), ...targets.map(p => p.watts)), ceiling = ResultChartLayout.ceiling(peak), minutes = end / 60;
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
  const targetLines = new Map(); for (const p of targets) { if (!targetLines.has(p.segment)) targetLines.set(p.segment, []); targetLines.get(p.segment).push(`${num(x(p.time))},${num(y(p.watts))}`); }
  svg += [...targetLines.values()].filter(l => l.length > 1).map(l => `<polyline class="target-line" points="${l.join(' ')}"/>`).join('');
  for (const b of bands) { const label = ResultChartLayout.fittingLabel(b.title, x(b.end) - x(b.start) - 8, 6.4); if (label) svg += `<text class="band-label" x="${num(x(b.start) + 4)}" y="${top + 13}">${esc(label)}</text>`; }
  if (best) {
    const text = ResultChartLayout.fittingLabel(best.title, plotW - 8, 7.6);
    if (text) { const width = ResultChartLayout.estimatedWidth(text, 7.6) + 8, at = left + ResultChartLayout.clampedLeading((x(best.start) + x(best.end)) / 2 - left, width, plotW); svg += `<rect class="best-label-bg" x="${num(at)}" y="${top + 19}" width="${num(width)}" height="17" rx="4"/><text class="best-label" x="${num(at + 4)}" y="${top + 32}">${esc(text)}</text>`; }
  }
  const phases = bands.map(b => `${b.title} minute ${Math.floor(b.start / 60)} to ${Math.floor(b.end / 60)}`).join(', '), bestText = best ? `${best.title} between minute ${Math.floor(best.start / 60)} and ${Math.floor(best.end / 60)}` : '';
  const source = session.configuration.powerSource === 'trainer' ? 'Trainer' : 'External power meter';
  svg += `<line class="hover-rule" x1="0" x2="0" y1="${top}" y2="${top + plotH}" visibility="hidden"/>`;
  return `<svg class="power-chart" data-hover="1" viewBox="0 0 ${W} ${H}" role="img" aria-label="Recorded power from ${source} over time${targets.length ? ", with the target power" : ""}. ${esc([phases, bestText].filter(Boolean).join('. '))}">${svg}</svg>`;
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

/** Recorded heart rate, drawn like the power chart (minutes along the bottom); nothing when no heart rate was recorded. */
export function heartRateChart(session) {
  const samples = session.samples.filter(s => Number.isFinite(s.heartRate) && s.heartRate > 0); if (samples.length < 2) return '';
  // The top margin is the title's own row, clear of the highest tick at the larger phone-width axis text.
  const W = 600, H = 172, left = 44, right = 10, top = 30, bottom = 30, plotW = W - left - right, plotH = H - top - bottom;
  const end = Math.max(60, session.endedAtOffset ?? session.samples.at(-1)?.time ?? 0), minutes = end / 60;
  const low = Math.floor((Math.min(...samples.map(s => s.heartRate)) - 5) / 10) * 10, high = Math.ceil((Math.max(...samples.map(s => s.heartRate)) + 5) / 10) * 10, span = Math.max(20, high - low);
  const x = seconds => left + (seconds / end) * plotW, y = bpm => top + plotH - ((bpm - low) / span) * plotH;
  let svg = ''; const step = span > 80 ? 20 : 10;
  for (let b = low; b <= low + span; b += step) svg += `<line class="grid" x1="${left}" x2="${W - right}" y1="${num(y(b))}" y2="${num(y(b))}"/><text class="axis" x="${left - 6}" y="${num(y(b) + 4)}" text-anchor="end">${b}</text>`;
  const every = minutes > 60 ? 15 : minutes > 25 ? 5 : minutes > 10 ? 2 : 1;
  for (let m = 0; m <= minutes; m += every) svg += `<text class="axis" x="${num(x(m * 60))}" y="${H - 12}" text-anchor="middle">${m}</text>`;
  svg += `<text class="axis-title" x="${num(left + plotW / 2)}" y="${H - 1}" text-anchor="middle">Minutes</text><text class="axis-title" x="10" y="15">bpm</text>`;
  const lines = []; let current = [], previous = null;
  for (const s of samples) { if (previous && s.time - previous.time > 5) { lines.push(current); current = []; } current.push(`${num(x(s.time))},${num(y(s.heartRate))}`); previous = s; }
  if (current.length) lines.push(current);
  svg += lines.filter(l => l.length > 1).map(l => `<polyline class="hr-line" points="${l.join(' ')}"/>`).join('');
  const sum = rideSummary(session);
  svg += `<line class="hover-rule" x1="0" x2="0" y1="${top}" y2="${top + plotH}" visibility="hidden"/>`;
  return `<svg class="power-chart hr-chart" data-hover="1" viewBox="0 0 ${W} ${H}" role="img" aria-label="Recorded heart rate over time. Average ${Math.round(sum.averageHeartRate ?? 0)} beats per minute, maximum ${sum.maximumHeartRate}.">${svg}</svg>`;
}
/** Left/right balance around an even 50 %: the left leg's share above the line, the right leg's below, smoothed over 30 seconds. Nothing when it was not reported. */
export function balanceChart(session) {
  const balance = rideBalance(session); if (!balance) return '';
  const points = balanceSeries(balance); if (points.length < 2) return '';
  const W = 600, H = 150, left = 44, right = 10, top = 8, bottom = 30, plotW = W - left - right, plotH = H - top - bottom;
  const end = Math.max(60, session.endedAtOffset ?? session.samples.at(-1)?.time ?? 0), minutes = end / 60, reach = balanceAxisReach(points);
  const x = seconds => left + (seconds / end) * plotW, y = share => top + plotH - ((share - (50 - reach)) / (2 * reach)) * plotH;
  let svg = '';
  for (const share of [50 - reach, 50 + reach]) svg += `<line class="grid" x1="${left}" x2="${W - right}" y1="${num(y(share))}" y2="${num(y(share))}"/><text class="axis" x="${left - 6}" y="${num(y(share) + 4)}" text-anchor="end">${share > 50 ? 'L' : 'R'} ${share > 50 ? share : 100 - share}</text>`;
  svg += `<text class="axis" x="${left - 6}" y="${num(y(50) + 4)}" text-anchor="end">50</text>`;
  const every = minutes > 60 ? 15 : minutes > 25 ? 5 : minutes > 10 ? 2 : 1;
  for (let m = 0; m <= minutes; m += every) svg += `<text class="axis" x="${num(x(m * 60))}" y="${H - 12}" text-anchor="middle">${m}</text>`;
  svg += `<text class="axis-title" x="${num(left + plotW / 2)}" y="${H - 1}" text-anchor="middle">Minutes</text>`;
  const segments = new Map(); for (const p of points) segments.set(p.segment, [...(segments.get(p.segment) ?? []), p]);
  for (const part of [...segments.values()].filter(s => s.length > 1)) {
    const area = pick => `M${num(x(part[0].time))},${num(y(50))} ${part.map(p => `L${num(x(p.time))},${num(y(pick(p.left)))}`).join(' ')} L${num(x(part.at(-1).time))},${num(y(50))} Z`;
    svg += `<path class="left-area" d="${area(v => Math.max(v, 50))}"/><path class="right-area" d="${area(v => Math.min(v, 50))}"/><polyline class="balance-line" points="${part.map(p => `${num(x(p.time))},${num(y(p.left))}`).join(' ')}"/>`;
  }
  svg += `<line class="even" x1="${left}" x2="${W - right}" y1="${num(y(50))}" y2="${num(y(50))}"/>`;
  svg += `<line class="hover-rule" x1="0" x2="0" y1="${top}" y2="${top + plotH}" visibility="hidden"/>`;
  const leftShare = Math.round(balance.left);
  return `<div class="row spread balance-head"><p class="label">Pedal balance</p><ul class="legend chart-legend"><li><span class="swatch balance-left"></span> Left ${leftShare} %</li><li><span class="swatch balance-right"></span> Right ${100 - leftShare} %</li></ul></div><svg class="power-chart balance-chart" data-hover="1" viewBox="0 0 ${W} ${H}" role="img" aria-label="Pedal balance over time. Left ${leftShare} percent, right ${100 - leftShare} percent overall.">${svg}</svg>`;
}
/** DFA α1 over the ride, one point per 30 s window (windows with too many artifacts or a gap are absent, so the line breaks there). Nothing without a series. */
export function alpha1Chart(session) {
  const hrv = heartRateVariability(session), points = hrv?.alpha1 ?? []; if (points.length < 2) return '';
  const W = 600, H = 150, left = 44, right = 10, top = 8, bottom = 30, plotW = W - left - right, plotH = H - top - bottom;
  const end = Math.max(60, session.endedAtOffset ?? session.samples.at(-1)?.time ?? 0), minutes = end / 60, ceiling = Math.max(1.5, Math.ceil(Math.max(...points.map(p => p.alpha1)) * 2) / 2);
  const x = seconds => left + (seconds / end) * plotW, y = v => top + plotH - (v / ceiling) * plotH;
  let svg = '';
  for (let v = 0; v <= ceiling + 0.001; v += 0.5) svg += `<line class="grid" x1="${left}" x2="${W - right}" y1="${num(y(v))}" y2="${num(y(v))}"/><text class="axis" x="${left - 6}" y="${num(y(v) + 4)}" text-anchor="end">${v.toFixed(1)}</text>`;
  for (const v of [0.75, 0.5]) svg += `<line class="reference" x1="${left}" x2="${W - right}" y1="${num(y(v))}" y2="${num(y(v))}"/>`;
  const every = minutes > 60 ? 15 : minutes > 25 ? 5 : minutes > 10 ? 2 : 1;
  for (let m = 0; m <= minutes; m += every) svg += `<text class="axis" x="${num(x(m * 60))}" y="${H - 12}" text-anchor="middle">${m}</text>`;
  svg += `<text class="axis-title" x="${num(left + plotW / 2)}" y="${H - 1}" text-anchor="middle">Minutes</text>`;
  const lines = []; let current = [], previous = null;
  for (const p of points) { if (previous && p.time - previous.time > 45) { lines.push(current); current = []; } current.push(`${num(x(p.time))},${num(y(p.alpha1))}`); previous = p; }
  if (current.length) lines.push(current);
  svg += lines.filter(l => l.length > 1).map(l => `<polyline class="alpha-line" points="${l.join(' ')}"/>`).join('');
  svg += `<line class="hover-rule" x1="0" x2="0" y1="${top}" y2="${top + plotH}" visibility="hidden"/>`;
  return `<p class="label">DFA α1</p><svg class="power-chart alpha-chart" data-hover="1" viewBox="0 0 ${W} ${H}" role="img" aria-label="DFA alpha 1 over time, a window every 30 seconds. 0.75 is about the aerobic threshold and 0.5 the anaerobic.">${svg}</svg><p class="footnote">0.75 ≈ aerobic threshold · 0.5 ≈ anaerobic</p>`;
}
const chartSessions = new Map();
/** Power with its target, a legend, and heart rate, DFA α1 and balance beneath when recorded. The wrapper carries what the hover needs (see `installRideHover`). */
export function rideCharts(session) {
  const hasTarget = targetSeries(session).length > 0, hr = heartRateChart(session), end = Math.max(60, session.endedAtOffset ?? session.samples.at(-1)?.time ?? 0), key = String(session.id ?? 'ride');
  chartSessions.set(key, session);
  const legend = `<ul class="legend chart-legend" aria-hidden="true"><li><span class="swatch power"></span> Power</li>${hasTarget ? '<li><span class="swatch target"></span> Target</li>' : ''}${hr ? '<li><span class="swatch hr"></span> Heart rate</li>' : ''}</ul>`;
  return `<div class="ride-charts" data-ride="${esc(key)}" data-end="${end}">${powerChart(session)}${legend}${hr}${alpha1Chart(session)}${balanceChart(session)}<div class="hover-card" hidden></div></div>`;
}

// ---- Hover readings: a vertical rule on every chart at the pointer's time, and a card on the chart under it. Only overlay nodes change; the paths are never redrawn. ----
const PLOT = { left: 44, right: 10, width: 600 };
function hoverRows(m) {
  const w = v => v == null ? null : `${Math.round(v)} W`, rows = [['Power', w(m.power)], ['Target', w(m.target)], ['Trainer', w(m.trainerPower)], ['Heart rate', m.heartRate == null ? null : `${Math.round(m.heartRate)} bpm`],
    ['Cadence', m.cadence == null ? null : `${Math.trunc(m.cadence)} rpm`], ['Left / right', m.leftBalance == null ? null : `${Math.round(m.leftBalance)} / ${100 - Math.round(m.leftBalance)} %`]];
  return rows.filter(r => r[1] != null);
}
function hoverAt(wrap, svg, clientX) {
  const session = chartSessions.get(wrap.dataset.ride), card = wrap.querySelector('.hover-card'); if (!session || !card) return;
  const box = svg.getBoundingClientRect(); if (!box.width) return;
  const vx = (clientX - box.left) / box.width * PLOT.width, end = Number(wrap.dataset.end), plot = PLOT.width - PLOT.left - PLOT.right;
  if (vx < PLOT.left || vx > PLOT.width - PLOT.right) return clearHover(wrap);
  const time = Math.min(end, Math.max(0, (vx - PLOT.left) / plot * end)), at = PLOT.left + time / end * plot;
  wrap.querySelectorAll('.hover-rule').forEach(r => { r.setAttribute('x1', at.toFixed(1)); r.setAttribute('x2', at.toFixed(1)); r.setAttribute('visibility', 'visible'); });
  const m = rideMoment(session, time), clock = `${Math.floor(time / 60)}:${String(Math.floor(time % 60)).padStart(2, '0')}`, rows = hoverRows(m);
  card.replaceChildren(); const head = document.createElement('strong'); head.textContent = clock; card.append(head);
  for (const [name, value] of rows) { const row = document.createElement('div'); row.textContent = `${name} ${value}`; card.append(row); }
  card.hidden = false;
  const wrapBox = wrap.getBoundingClientRect(), cardWidth = card.offsetWidth, x = box.left - wrapBox.left + at / PLOT.width * box.width, flip = x + cardWidth + 12 > wrapBox.width;
  card.style.left = `${Math.max(0, flip ? x - cardWidth - 8 : x + 8)}px`; card.style.top = `${svg.getBoundingClientRect().top - wrapBox.top + 4}px`;
}
function clearHover(wrap) { wrap.querySelectorAll('.hover-rule').forEach(r => r.setAttribute('visibility', 'hidden')); const card = wrap.querySelector('.hover-card'); if (card) card.hidden = true; }
let hoverInstalled = false;
export function installRideHover() {
  if (hoverInstalled || typeof document === 'undefined') return; hoverInstalled = true;
  const target = e => { const svg = e.target.closest?.('svg[data-hover]'); return svg ? [svg.closest('.ride-charts'), svg] : [null, null]; };
  document.addEventListener('pointermove', e => { const [wrap, svg] = target(e); if (wrap) hoverAt(wrap, svg, e.clientX); });
  document.addEventListener('pointerdown', e => { const [wrap, svg] = target(e); if (wrap) hoverAt(wrap, svg, e.clientX); });
  document.addEventListener('pointerleave', e => { document.querySelectorAll('.ride-charts').forEach(clearHover); }, true);
  document.addEventListener('pointerout', e => { const wrap = e.target.closest?.('.ride-charts'); if (wrap && !wrap.contains(e.relatedTarget)) clearHover(wrap); });
}
installRideHover();
/** Time, average and normalized power, heart rate and cadence for a finished ride. Figures that were not recorded are left out. */
export function summaryCard(session) {
  if (!session.samples?.length) return '';
  const s = rideSummary(session), power = session.training?.resistance == null, round = n => Math.round(n), hrv = heartRateVariability(session);
  const items = [['Time', DurationFormat.clock(s.duration)], power && s.averagePower != null && ['Average power', `${round(s.averagePower)} W`], power && s.normalizedPower != null && ['Normalized power', `${round(s.normalizedPower)} W`],
    s.trainerAveragePower != null && ['Trainer power (average)', `${round(s.trainerAveragePower)} W`], s.trainerNormalizedPower != null && ['Trainer power (normalized)', `${round(s.trainerNormalizedPower)} W`],
    s.averageHeartRate != null && ['Average heart rate', `${round(s.averageHeartRate)} bpm`], s.maximumHeartRate != null && ['Max heart rate', `${s.maximumHeartRate} bpm`], s.averageCadence != null && ['Average cadence', `${round(s.averageCadence)} rpm`], hrv?.rmssd != null && ['HRV (RMSSD)', `${round(hrv.rmssd)} ms`], hrv && hrv.artifactShare >= 0.01 && ['Beat artifacts', `${round(hrv.artifactShare * 100)} %`],
    s.kilojoules != null && ['Energy', `${round(s.kilojoules)} kJ`], s.kilocalories != null && ['Estimated calories', `${round(s.kilocalories)} kcal`], s.distance != null && ['Simulated distance', `${(s.distance / 1000).toFixed(2)} km`],
    s.leftBalance != null && ['Left / right', `${round(s.leftBalance)} / ${100 - round(s.leftBalance)} %`]].filter(Boolean);
  return `<section class="card summary-grid" id="ride-summary">${items.map(([t, v]) => `<div><p class="label">${esc(t)}</p><p class="num big">${esc(v)}</p></div>`).join('')}</section>`;
}
