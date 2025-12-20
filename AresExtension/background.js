/**
 * Ares Analysis 2.0 - Professional Telemetry Extension
 * Standardized Beacon-style transport for unbreakable data flow.
 */

const ARES_API = 'http://127.0.0.1:10086';
const requestTimes = new Map();

// --- Transport Layer (Batched POST) ---
let telemetryQueue = [];
let batchTimeout = null;

async function transmitTelemetry(payload) {
    telemetryQueue.push(payload);

    // Clear existing timeout if any
    if (batchTimeout) clearTimeout(batchTimeout);

    // If buffer is large, send immediately
    if (telemetryQueue.length >= 20) {
        await flushTelemetry();
    } else {
        // Otherwise wait a bit to collect more
        batchTimeout = setTimeout(flushTelemetry, 200);
    }
}

async function flushTelemetry() {
    if (telemetryQueue.length === 0) return;

    const body = JSON.stringify(telemetryQueue);
    const count = telemetryQueue.length;
    telemetryQueue = [];
    if (batchTimeout) clearTimeout(batchTimeout);
    batchTimeout = null;

    try {
        // Now using default 'cors' mode because Swift server handles OPTIONS preflight
        const response = await fetch(ARES_API, {
            method: 'POST',
            credentials: 'omit',
            body: body
        });

        if (response.ok) {
            updateBadge("ON", "#4CAF50");
        } else {
            console.warn(`[Ares] ⚠️ Telemetry server returned status ${response.status}`);
            updateBadge("ERR", "#F44336");
        }
    } catch (e) {
        console.error(`[Ares] ❌ Telemetry failed (${count} items):`, e.message || e);

        // Final fallback to localhost
        try {
            await fetch(ARES_API.replace('127.0.0.1', 'localhost'), {
                method: 'POST',
                body: body
            });
            updateBadge("ON", "#4CAF50");
        } catch (err2) {
            updateBadge("ERR", "#F44336");
        }
    }
}

function updateBadge(text, color) {
    chrome.action.setBadgeText({ text });
    chrome.action.setBadgeBackgroundColor({ color });
}

// --- Tab Lifecycle Monitoring ---

function syncTab(tab) {
    if (!tab || !tab.url || tab.url.startsWith('chrome://')) return;
    transmitTelemetry({
        id: tab.id.toString(),
        url: tab.url,
        title: tab.title || 'Untitled',
        lastUpdate: new Date().toISOString()
    });
}

// More aggressive tab syncing for SPA and title updates
chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
    // Sync on any change that might be a title or URL update (SPA navigation)
    if (changeInfo.status === 'complete' || changeInfo.title || changeInfo.url) {
        syncTab(tab);
    }
});

chrome.tabs.onActivated.addListener((activeInfo) => {
    chrome.tabs.get(activeInfo.tabId, (tab) => {
        if (!chrome.runtime.lastError && tab) syncTab(tab);
    });
});

chrome.tabs.onRemoved.addListener((tabId) => {
    transmitTelemetry({
        tabId: tabId.toString(),
        tabRemoved: true
    });
});

// SPA & History Support: Catch title/URL changes that don't trigger 'complete'
chrome.webNavigation.onHistoryStateUpdated.addListener((details) => {
    if (details.tabId === -1) return;
    chrome.tabs.get(details.tabId, (tab) => {
        if (!chrome.runtime.lastError && tab) syncTab(tab);
    });
});

chrome.webNavigation.onReferenceFragmentUpdated.addListener((details) => {
    if (details.tabId === -1) return;
    chrome.tabs.get(details.tabId, (tab) => {
        if (!chrome.runtime.lastError && tab) syncTab(tab);
    });
});

// --- Professional Network Monitoring ---

chrome.webRequest.onBeforeRequest.addListener(
    (details) => {
        if (details.tabId === -1) return;
        requestTimes.set(details.requestId, details.timeStamp);
    },
    { urls: ["<all_urls>"] }
);

chrome.webRequest.onBeforeSendHeaders.addListener(
    (details) => {
        if (details.tabId === -1) return;
        const headers = {};
        details.requestHeaders.forEach(h => headers[h.name] = h.value);

        transmitTelemetry({
            tabId: details.tabId.toString(),
            request: {
                id: details.requestId,
                url: details.url,
                method: details.method,
                type: details.type,
                timestamp: new Date().toISOString(),
                status: 'pending',
                requestHeaders: headers
            }
        });
    },
    { urls: ["<all_urls>"] },
    ["requestHeaders"]
);

chrome.webRequest.onResponseStarted.addListener(
    (details) => {
        if (details.tabId === -1) return;

        const headers = {};
        if (details.responseHeaders) {
            details.responseHeaders.forEach(h => headers[h.name] = h.value);
        }

        transmitTelemetry({
            tabId: details.tabId.toString(),
            request: {
                id: details.requestId,
                url: details.url,
                method: details.method,
                type: details.type,
                timestamp: new Date().toISOString(),
                status: 'active',
                statusCode: details.statusCode,
                mimeType: headers['Content-Type'] || headers['content-type'],
                size: parseInt(headers['Content-Length'] || headers['content-length'] || "0"),
                remoteAddress: details.ip,
                responseHeaders: headers
            }
        });
    },
    { urls: ["<all_urls>"] },
    ["responseHeaders"]
);

chrome.webRequest.onCompleted.addListener(
    (details) => {
        if (details.tabId === -1) return;

        const startTime = requestTimes.get(details.requestId);
        const duration = startTime ? (details.timeStamp - startTime) / 1000 : 0;
        requestTimes.delete(details.requestId);

        transmitTelemetry({
            tabId: details.tabId.toString(),
            request: {
                id: details.requestId,
                url: details.url,
                method: details.method,
                type: details.type,
                timestamp: new Date().toISOString(),
                status: 'success',
                statusCode: details.statusCode,
                duration: duration
            }
        });
    },
    { urls: ["<all_urls>"] }
);

chrome.webRequest.onErrorOccurred.addListener(
    (details) => {
        if (details.tabId === -1) return;
        requestTimes.delete(details.requestId);

        transmitTelemetry({
            tabId: details.tabId.toString(),
            request: {
                id: details.requestId,
                url: details.url,
                method: details.method,
                type: details.type,
                timestamp: new Date().toISOString(),
                status: 'error',
                errorMessage: details.error
            }
        });
    },
    { urls: ["<all_urls>"] }
);

// --- Message Relay ---
chrome.runtime.onMessage.addListener((message, sender) => {
    if (message.type === 'BODY_CAPTURE' && sender.tab) {
        transmitTelemetry({
            tabId: sender.tab.id.toString(),
            request: {
                // Heuristic ID matching: We don't have requestId in the page context,
                // so we send URL/Method and let Ares merge it based on recent activity.
                id: `body-${Date.now()}`,
                url: message.url,
                method: message.method,
                status: 'active',
                requestBody: message.requestBody,
                responseBody: message.responseBody,
                timestamp: new Date().toISOString(),
                type: 'fetch' // Body capture is usually XHR/Fetch
            }
        });
    }
});

// --- Maintenance Sync ---

chrome.alarms.onAlarm.addListener((alarm) => {
    if (alarm.name === 'heartbeat') {
        chrome.tabs.query({}, (tabs) => {
            tabs.forEach(syncTab);
        });
    }
});

chrome.alarms.create('heartbeat', { periodInMinutes: 0.5 });

// Initial startup sync
console.log('[Ares] 🚀 Analysis 2.0 Monitoring Active');
chrome.tabs.query({}, (tabs) => {
    tabs.forEach(syncTab);
});
