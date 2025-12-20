/**
 * Ares Injection Script
 * Hooks into fetch and XHR to capture request/response bodies.
 */
(function () {
    if (window.aresInjected) return;
    window.aresInjected = true;

    const ORIGIN = 'ares-bridge';

    function sendToExtension(payload) {
        window.postMessage({ source: ORIGIN, payload: payload }, '*');
    }

    // --- Hook Fetch ---
    const originalFetch = window.fetch;
    window.fetch = async (...args) => {
        const url = args[0] instanceof Request ? args[0].url : args[0];
        const method = (args[0] instanceof Request ? args[0].method : args[1]?.method) || 'GET';

        // Capture request body
        let requestBody = null;
        if (args[0] instanceof Request) {
            try { requestBody = await args[0].clone().text(); } catch (e) { }
        } else if (args[1]?.body) {
            requestBody = args[1].body;
        }

        const response = await originalFetch(...args);

        // We only care about text-like responses
        const contentType = response.headers.get('content-type') || '';
        if (contentType.includes('json') || contentType.includes('text') || contentType.includes('javascript') || contentType.includes('xml')) {
            try {
                const clone = response.clone();
                const body = await clone.text();
                // Send update for this URL/Method/Body
                // Note: We don't have the exact chrome-internal requestId here,
                // so we use URL+Method+Timestamp as a heuristic for background correlation.
                sendToExtension({
                    type: 'BODY_CAPTURE',
                    url: url,
                    method: method,
                    requestBody: typeof requestBody === 'string' ? requestBody : null,
                    responseBody: body
                });
            } catch (e) { }
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
            const contentType = this.getResponseHeader('content-type') || '';
            if (contentType.includes('json') || contentType.includes('text') || contentType.includes('javascript') || contentType.includes('xml')) {
                sendToExtension({
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

    console.log('[Ares] 🔍 Payload inspection active');
})();
