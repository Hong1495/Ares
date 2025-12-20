/**
 * Ares Content Script (Isolated World)
 * Bridge between MAIN world hooks and Background Service Worker.
 */

window.addEventListener('AresPayloadEvent', (event) => {
    if (event.detail && typeof chrome !== 'undefined' && chrome.runtime && chrome.runtime.id) {
        try {
            chrome.runtime.sendMessage(event.detail);
        } catch (e) {
            // Silently ignore context invalidation
        }
    }
});

console.log('[Ares] 🌉 Bridge active');
