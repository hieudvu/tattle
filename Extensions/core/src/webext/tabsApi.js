// Adapter over chrome.* / browser.* tab APIs. Every call is awaited, so it works with
// callback-style chrome.* and Promise-style browser.* / MV3 chrome.* alike.
import { parseTabProtocolId } from '../tabSnapshot.js';

// Pauses every <video>/<audio> in the frame it runs in. Must be self-contained: it is serialized.
export function pauseMediaInFrame() {
  let paused = 0;
  for (const el of document.querySelectorAll('video, audio')) {
    try {
      if (!el.paused) {
        el.pause();
        paused += 1;
      }
    } catch { /* ignore a media element that refuses */ }
  }
  return paused;
}

// Tab change events that can alter the protocol snapshot.
const RELEVANT_CHANGE_KEYS = ['audible', 'mutedInfo', 'title', 'url'];

export function createWebExtTabsApi(api) {
  async function resolveTab(protocolId) {
    const parsed = parseTabProtocolId(protocolId);
    if (!parsed) throw new Error('tab not found');
    let tab = null;
    try {
      tab = await api.tabs.get(parsed.tabId);
    } catch {
      tab = null;
    }
    if (!tab || tab.windowId !== parsed.windowId) throw new Error('tab not found');
    return { tab, tabId: parsed.tabId, windowId: parsed.windowId };
  }

  return {
    queryAll() {
      return api.tabs.query({});
    },

    onChanged(cb) {
      const onUpdated = (_tabId, changeInfo) => {
        if (changeInfo && RELEVANT_CHANGE_KEYS.some((k) => k in changeInfo)) cb();
      };
      const onCreated = () => cb();
      const onRemoved = () => cb();
      const onReplaced = () => cb();
      api.tabs.onUpdated.addListener(onUpdated);
      api.tabs.onCreated.addListener(onCreated);
      api.tabs.onRemoved.addListener(onRemoved);
      api.tabs.onReplaced.addListener(onReplaced);
      return () => {
        api.tabs.onUpdated.removeListener(onUpdated);
        api.tabs.onCreated.removeListener(onCreated);
        api.tabs.onRemoved.removeListener(onRemoved);
        api.tabs.onReplaced.removeListener(onReplaced);
      };
    },

    async setMuted(protocolId, muted) {
      const { tabId } = await resolveTab(protocolId);
      await api.tabs.update(tabId, { muted });
    },

    async pause(protocolId) {
      const { tabId } = await resolveTab(protocolId);
      const results = await api.scripting.executeScript({
        target: { tabId, allFrames: true },
        func: pauseMediaInFrame,
      });
      // Report a pause that did nothing instead of claiming success (e.g. the page lost the
      // player, or the browser only allowed some frames).
      if (Array.isArray(results) && results.length > 0 &&
          results.every((r) => r && typeof r.result === 'number') &&
          results.reduce((n, r) => n + r.result, 0) === 0) {
        throw new Error('nothing was playing in that tab');
      }
    },

    async close(protocolId) {
      const { tabId } = await resolveTab(protocolId);
      await api.tabs.remove(tabId);
    },

    async focus(protocolId) {
      const { tabId, windowId } = await resolveTab(protocolId);
      await api.tabs.update(tabId, { active: true });
      await api.windows.update(windowId, { focused: true });
    },
  };
}
