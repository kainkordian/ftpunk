export const CITY_BEATS = [
  { id: 'last-light-route', milliseconds: 0, title: 'A signal in the static', speaker: 'Nami', message: 'The Lowline radio is quiet. I marked a route between the rooftops. No sprint required. Just keep showing up; we will keep the channel open.' },
  { id: 'last-light-parts', milliseconds: 300000, title: 'The repair bench', speaker: 'Mara', message: 'The transmitter still has a pulse. Your route brought the spare parts home. I have a coil, a switch, and a reason to leave the workshop light on.' },
  { id: 'last-light-carrier', milliseconds: 600000, title: 'Carrier detected', speaker: 'HEX', message: 'Signal found. Three windows on the Lowline are answering. Keep your own pace. The channel will wait for you.' },
  { id: 'last-light-radio', milliseconds: 1200000, title: 'Lowline is on air', speaker: 'Nami', message: 'Mara turns the final dial. Static breaks into a voice: Lowline, you are back on air. A Last Light patch is waiting at your door. This corner of the city remembers you.' },
];
export function rideRewards(session) {
  const milliseconds = session.isDemo || !session.adventureEnabled ? 0 : session.eligibleMilliseconds ?? 0, start = session.adventureStartMilliseconds;
  return { milliseconds, xp: Math.floor(milliseconds / 6000), partial: milliseconds % 6000, unlocked: session.isDemo || start == null ? [] : CITY_BEATS.filter(b => b.milliseconds > start && b.milliseconds <= start + milliseconds) };
}
// Original vector artwork: progress changes the scene; no animation or trainer input.
export function cityScene(ms = 0) {
  const onAir = ms >= 1200000, rect = (x, y, w, h, fill) => `<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${fill}"/>`;
  let shapes = rect(0, 0, 320, 180, '#0a1421');
  for (let i = 0; i < 22; i++) shapes += rect((i * 73 + 17) % 320, (i * 19 + 9) % 70, 1, 1, '#8c99a6');
  shapes += rect(255, 18, 18, 18, '#bdd9b8');
  for (let i = 0; i < 9; i++) {
    const x = i * 39 - 8, top = 55 + i * 31 % 49; shapes += rect(x, top, 32, 110, '#172e3b');
    for (let row = 0; row < 5; row++) for (let col = 0; col < 3; col++) shapes += rect(x + 5 + col * 9, top + 9 + row * 15, 4, 6, ms >= 600000 && (i + row + col) % 3 === 0 ? '#d6ca6a' : '#1e4650');
  }
  shapes += rect(0, 146, 320, 34, '#141f29') + rect(0, 149, 320, 2, '#287d84') + rect(19, 111, 72, 36, '#2b3845') + rect(24, 120, 46, 21, ms >= 300000 ? '#df9851' : '#111922') + rect(76, 122, 9, 25, '#10151b');
  shapes += rect(205, 103, 60, 44, '#21404d') + rect(230, 49, 3, 54, '#8b9496') + rect(215, 57, 33, 2, '#8b9496') + rect(221, 67, 22, 2, '#8b9496') + rect(215, 114, 40, 14, onAir ? '#9fed93' : '#9b496b') + rect(228, 40, 7, 7, onAir ? '#9fed93' : '#e2789d');
  if (onAir) for (let i = 0; i < 3; i++) shapes += rect(218 - i * 7, 34 - i * 6, 27 + i * 14, 1, '#6bcd9b');
  for (let i = 0; i < 5; i++) shapes += rect(25 + i * 65, 166, 28, 2, '#505860');
  return `<svg class="city-scene" viewBox="0 0 320 180" role="img" aria-label="${onAir ? 'Lowline at night, windows lit and the radio on air' : 'Lowline at night, a workshop and a silent rooftop radio'}" xmlns="http://www.w3.org/2000/svg">${shapes}<text x="24" y="108" fill="white" font-family="monospace" font-size="12" font-weight="bold">LOWLINE</text><text x="219" y="124" fill="#091519" font-family="monospace" font-size="7" font-weight="bold">${onAir ? 'ON AIR' : 'STATIC'}</text></svg>`;
}
