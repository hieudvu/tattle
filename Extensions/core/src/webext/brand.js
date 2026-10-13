// Detects the real Chromium-family brand. Firefox never calls this (it is always "firefox").
// Arc cannot be told apart from Chrome by UA, so it is reported as chrome.
// nav: a navigator-like object (userAgent, optional brave.isBrave()).

export async function detectChromiumBrand(nav) {
  const ua = (nav && nav.userAgent) || '';
  if (nav && nav.brave && typeof nav.brave.isBrave === 'function') {
    try {
      if (await nav.brave.isBrave()) return 'brave';
    } catch { /* not brave */ }
  }
  if (ua.includes('Edg/')) return 'edge';
  if (ua.includes('OPR/')) return 'opera';
  if (ua.includes('Vivaldi')) return 'vivaldi';
  return 'chrome';
}
