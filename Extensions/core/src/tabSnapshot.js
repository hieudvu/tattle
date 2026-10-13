// Pure mapping from raw browser tabs (chrome.tabs / browser.tabs shape) to protocol tabs.

export function tabProtocolId(windowId, tabId) {
  return `${windowId}:${tabId}`;
}

// Splits "<windowId>:<tabId>" back into numbers. Returns null for anything malformed.
export function parseTabProtocolId(id) {
  if (typeof id !== 'string') return null;
  const m = /^(\d+):(\d+)$/.exec(id);
  if (!m) return null;
  return { windowId: Number(m[1]), tabId: Number(m[2]) };
}

function isMuted(tab) {
  if (tab.mutedInfo && typeof tab.mutedInfo.muted === 'boolean') return tab.mutedInfo.muted;
  return tab.muted === true;
}

// Keeps only tabs that are audible or muted (a muted tab must stay listed so it can be unmuted).
export function toProtocolTabs(rawTabs) {
  const out = [];
  for (const tab of Array.isArray(rawTabs) ? rawTabs : []) {
    if (!tab || typeof tab !== 'object') continue;
    if (typeof tab.id !== 'number' || typeof tab.windowId !== 'number') continue;
    const audible = tab.audible === true;
    const muted = isMuted(tab);
    if (!audible && !muted) continue;
    out.push({
      id: tabProtocolId(tab.windowId, tab.id),
      title: typeof tab.title === 'string' ? tab.title : '',
      url: typeof tab.url === 'string' ? tab.url : '',
      audible,
      muted,
    });
  }
  return out;
}
