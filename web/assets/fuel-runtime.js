(() => {
  const active = new Map();
  const base = 'sounds/fuel/';
  const known = new Set([
    'pickupnozzle', 'putbacknozzle', 'putbackcharger',
    'refuel', 'fuelstop', 'charging', 'chargestop'
  ]);

  const stop = (name) => {
    const audio = active.get(name);
    if (!audio) return;
    try {
      audio.pause();
      audio.currentTime = 0;
    } catch (_) {}
    active.delete(name);
  };

  const play = (name, volume, loop) => {
    if (!known.has(name)) return;
    stop(name);
    const audio = new Audio(`${base}${name}.ogg`);
    audio.volume = Math.max(0, Math.min(1, Number(volume) || 0.45));
    audio.loop = loop === true;
    active.set(name, audio);
    audio.addEventListener('ended', () => {
      if (!audio.loop) active.delete(name);
    }, { once: true });
    audio.play().catch(() => active.delete(name));
  };

  window.addEventListener('message', (event) => {
    const data = event.data || {};
    if (data.action !== 'psFuelSound') return;
    if (data.command === 'stop') stop(String(data.name || ''));
    if (data.command === 'stopAll') {
      [...active.keys()].forEach(stop);
      return;
    }
    if (data.command === 'play') play(String(data.name || ''), data.volume, data.loop);
  });
})();
