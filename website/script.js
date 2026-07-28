// Illustration only. No timer state, storage, audio, or network requests.
(() => {
  const total = 25 * 60;
  const initial = 18 * 60 + 42;
  const start = Date.now();
  const clocks = document.querySelectorAll('[data-clock]');
  const fills = document.querySelectorAll('[data-fill]');
  function render() {
    const elapsed = Math.floor((Date.now() - start) / 1000);
    const remaining = ((initial - elapsed) % total + total) % total;
    const time = `${String(Math.floor(remaining / 60)).padStart(2, '0')}:${String(remaining % 60).padStart(2, '0')}`;
    clocks.forEach(clock => { clock.textContent = time; });
    fills.forEach(fill => { fill.style.width = `${(1 - remaining / total) * 100}%`; });
  }
  render();
  setInterval(render, 1000);
})();
