// Apply the saved choice before styles paint. Until a choice is made, follow the system.
(() => {
  const key = 'stint-theme';
  const system = window.matchMedia('(prefers-color-scheme: light)');
  let preference = null;
  try {
    const saved = localStorage.getItem(key);
    if (saved === 'light' || saved === 'dark') preference = saved;
  } catch { /* The toggle still works when storage is unavailable. */ }

  function apply() {
    const theme = preference || (system.matches ? 'light' : 'dark');
    document.documentElement.dataset.theme = theme;
    document.querySelectorAll('meta[name="theme-color"]').forEach(meta => {
      meta.content = theme === 'light' ? '#F4F3F0' : '#111214';
      meta.removeAttribute('media');
    });
    const button = document.getElementById('theme-toggle');
    if (button) {
      const label = `Switch to ${theme === 'dark' ? 'light' : 'dark'} mode`;
      button.setAttribute('aria-label', label);
      button.title = label;
      button.hidden = false;
    }
  }

  apply();
  system.addEventListener('change', () => { if (!preference) apply(); });
  document.addEventListener('DOMContentLoaded', () => {
    apply();
    document.getElementById('theme-toggle').addEventListener('click', () => {
      preference = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
      try { localStorage.setItem(key, preference); } catch { /* Keep this visit usable. */ }
      apply();
    });
  });
})();
