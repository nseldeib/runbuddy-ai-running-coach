const { createIssue } = require("./scenario-issues");

// Known substrings that mean the app refused to initialize because it was loaded
// from an *insecure context* — a bare dotted-quad IP rather than HTTPS or the
// hostname `localhost`. This is a whole CLASS of failure (Sveltia CMS's
// "only works with HTTPS or localhost", anything gating on `isSecureContext`,
// `crypto.subtle`, service workers, `Secure` cookies, WebAuthn), not one app.
// Matching reclassifies the error as an actionable `insecure-host` advisory
// instead of a generic console/page failure that surfaces as a bare
// `screenshot=null` with no explanation. Substrings are matched
// case-insensitively; keep the set small and well-known.
const INSECURE_CONTEXT_SIGNATURES = [
  "only works with https or localhost",
  "issecurecontext",
  "secure context",
  "requires https",
];

// The single actionable message the `insecure-host` advisory carries. Names the
// class of failure and the fix (the preview origin is `localhost` by default;
// stubborn apps can opt into HTTPS) rather than echoing one app's raw error.
const INSECURE_HOST_ADVISORY_MESSAGE =
  "The app refused to run because it was loaded from an insecure context " +
  "(a bare IP). It requires a secure context — HTTPS or the hostname " +
  "`localhost`. The preview origin is `localhost` by default; if this persists, " +
  "the app may require HTTPS even on localhost — enable `proxy.httpsPreview` in " +
  ".codeyam/editor.json.";

// Reclassify an error string as an `insecure-host` advisory when it matches a
// known insecure-context signature, else null. Pure; the original text is kept
// as the `contextSnippet` so the operator can still see what the app logged.
function insecureContextAdvisory(text) {
  if (typeof text !== "string" || text.length === 0) return null;
  const lower = text.toLowerCase();
  const matched = INSECURE_CONTEXT_SIGNATURES.some((sig) => lower.includes(sig));
  if (!matched) return null;
  return createIssue("insecure-host", INSECURE_HOST_ADVISORY_MESSAGE, {
    contextSnippet: text,
  });
}

function getInitScript() {
  return `
    window.__codeyamUnhandledRejections = [];
    window.addEventListener("unhandledrejection", (event) => {
      const reason = event.reason;
      const message =
        reason instanceof Error ? reason.message : String(reason);
      window.__codeyamUnhandledRejections.push(message);
    });

    // Stub WebSocket during capture to prevent terminal reconnection spam.
    window.WebSocket = class StubWebSocket {
      static CONNECTING = 0;
      static OPEN = 1;
      static CLOSING = 2;
      static CLOSED = 3;
      readyState = 3;
      onopen = null;
      onclose = null;
      onerror = null;
      onmessage = null;
      send() {}
      close() {}
      addEventListener() {}
      removeEventListener() {}
      dispatchEvent() { return false; }
      constructor() {
        setTimeout(() => {
          if (this.onerror) this.onerror(new Event("error"));
          if (this.onclose) this.onclose(new CloseEvent("close"));
        }, 0);
      }
    };
  `;
}

function handleConsoleMessage(message) {
  if (message.type() !== "error") return null;
  const text = message.text();

  // An insecure-context refusal wins over the generic `console` classification:
  // it is the targeted, actionable signal for the secure-context app class.
  const advisory = insecureContextAdvisory(text);
  if (advisory) return advisory;

  // Ignore known dev-server WebSocket/HMR errors from Vite proxy
  if (
    text.includes("WebSocket connection to") ||
    text.includes("Unsupported Media Type")
  ) {
    return null;
  }

  // Ignore the browser's blocked-script warning for sandboxed mockup-preview
  // frames. Mockup previews render untrusted AI-generated HTML inside a
  // `sandbox=""` iframe; the HTML-injection proxy injects an error-capture
  // <script> tag, which the browser then refuses to run, emitting
  // "Blocked script execution ... because the frame is sandboxed". That block
  // is the capture's own injected script being denied — benign for capture
  // purposes. Match narrowly on BOTH the block phrase and the "sandboxed"
  // signature so a genuine non-sandbox CSP block ("Blocked script execution"
  // without "sandboxed") still surfaces as a real issue.
  if (
    text.includes("Blocked script execution") &&
    text.includes("sandboxed")
  ) {
    return null;
  }

  return createIssue("console", text);
}

function handlePageError(error) {
  const text = error.message || String(error);
  // A secure-context guard often throws at boot rather than logging — surface
  // the same actionable advisory for the pageerror path.
  const advisory = insecureContextAdvisory(text);
  if (advisory) return advisory;
  return createIssue("pageerror", text);
}

function handleRequestFailed(request) {
  const errorText = request.failure()?.errorText || "Request failed";

  // Filter benign request cancellations. `net::ERR_ABORTED` is what Playwright
  // emits when a request is in-flight at the moment the page is closed (or the
  // iframe is destroyed). For scenarios whose pages fetch large payloads (the
  // editor's own EditorShell mounts a 2.2MB `/api/tests` fetch), the
  // browser.close() at the end of capture races the fetch and produces this
  // event AFTER the screenshot has already been taken — there is no real
  // failure to surface. Genuine network failures arrive under different
  // codes (net::ERR_CONNECTION_REFUSED, net::ERR_NAME_NOT_RESOLVED, etc.)
  // and continue to be reported.
  if (errorText.includes("net::ERR_ABORTED")) {
    return null;
  }

  return createIssue("requestfailed", errorText, { url: request.url() });
}

module.exports = {
  getInitScript,
  handleConsoleMessage,
  handlePageError,
  handleRequestFailed,
  insecureContextAdvisory,
  INSECURE_CONTEXT_SIGNATURES,
  INSECURE_HOST_ADVISORY_MESSAGE,
};
