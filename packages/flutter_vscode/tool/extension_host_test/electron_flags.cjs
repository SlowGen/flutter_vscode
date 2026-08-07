'use strict';

// Chromium suspends requestAnimationFrame in fully occluded windows. On a
// developer desktop the headed test window routinely opens behind other
// windows, so a perfectly healthy Flutter View never produces its first
// frame and every render-confirmation milestone times out — the engine
// logs boot activity, then silence. Seen three times before diagnosis:
// twice as apparent budget flakes, once as a five-minute timeout with a
// demonstrably live renderer. These flags keep test-window renderers
// scheduled regardless of visibility and focus.
module.exports.renderStabilityFlags = [
  '--disable-renderer-backgrounding',
  '--disable-backgrounding-occluded-windows',
  '--disable-background-timer-throttling',
];
