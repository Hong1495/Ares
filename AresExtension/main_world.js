/**
 * Ares Main World Script
 * Injected directly into the page context to hook fetch and XHR.
 * This runs in the "MAIN" world, avoiding postMessage complexity.
 */
(function () {
    if (window.aresInjected) return;
    window.aresInjected = true;

    console.log('[Ares] 🔍 Injecting Payload Hooks...');

    // Helper to send data to background (via a custom event that content script can hear, 
    // OR just use chrome.runtime if permissions allow, but usually MAIN world can't)
    // Actually, MAIN world CANNOT use chrome.runtime. 
    // So we still need a bridge event to the ISOLATED world (content script).
    function notifyBridge(payload) {
        const event = new CustomEvent('AresPayloadEvent', { detail: payload });
        window.dispatchEvent(event);
    }

    // --- Hook Fetch ---
    const originalFetch = window.fetch;
    window.fetch = async (...args) => {
        const url = args[0] instanceof Request ? args[0].url : args[0];
        const method = (args[0] instanceof Request ? args[0].method : args[1]?.method) || 'GET';
        const fullUrl = (new URL(url, window.location.href)).href;

        let requestBody = null;
        if (args[0] instanceof Request) {
            try { requestBody = await args[0].clone().text(); } catch (e) { }
        } else if (args[1]?.body) {
            requestBody = args[1].body;
        }

        const response = await originalFetch(...args);

        const contentType = (response.headers.get('content-type') || '').toLowerCase();
        const isInspectable = contentType.includes('json') ||
            contentType.includes('text') ||
            contentType.includes('javascript') ||
            contentType.includes('xml');

        if (isInspectable) {
            try {
                const clone = response.clone();
                const body = await clone.text();
                notifyBridge({
                    type: 'BODY_CAPTURE',
                    url: fullUrl,
                    method: method,
                    requestBody: typeof requestBody === 'string' ? requestBody : null,
                    responseBody: body
                });
            } catch (e) {
                console.error('[Ares] Fetch body capture failed:', e);
            }
        }

        return response;
    };

    // --- Hook XHR ---
    const XHR = XMLHttpRequest.prototype;
    const originalOpen = XHR.open;
    const originalSend = XHR.send;

    XHR.open = function (method, url) {
        this._aresMethod = method;
        this._aresUrl = (new URL(url, window.location.href)).href;
        return originalOpen.apply(this, arguments);
    };

    XHR.send = function (body) {
        this._aresRequestBody = body;
        this.addEventListener('load', function () {
            const contentType = (this.getResponseHeader('content-type') || '').toLowerCase();
            const isInspectable = contentType.includes('json') ||
                contentType.includes('text') ||
                contentType.includes('javascript') ||
                contentType.includes('xml');

            if (isInspectable) {
                notifyBridge({
                    type: 'BODY_CAPTURE',
                    url: this._aresUrl,
                    method: this._aresMethod,
                    requestBody: typeof this._aresRequestBody === 'string' ? this._aresRequestBody : null,
                    responseBody: this.responseText
                });
            }
        });
        return originalSend.apply(this, arguments);
    };

    console.log('[Ares] ✅ Payload hooks active');
})();
