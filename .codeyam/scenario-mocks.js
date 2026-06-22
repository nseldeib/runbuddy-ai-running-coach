function normalizeMockCandidates(url) {
  try {
    const parsed = new URL(url);
    return [url, `${parsed.pathname}${parsed.search}`, parsed.pathname];
  } catch {
    return [url];
  }
}

function findHttpMock(httpMocks, request) {
  const method = request.method().toUpperCase();
  const candidates = normalizeMockCandidates(request.url());
  for (const candidate of candidates) {
    const key = `${method} ${candidate}`;
    if (httpMocks[key]) {
      return httpMocks[key];
    }
  }
  return null;
}

// The set of path/URL targets declared by the mock keys. A key is
// `"<METHOD> <target>"` (e.g. `"GET /api/plans"`); we strip the method so the
// route matcher can decide whether a request *could* match any mock without
// knowing the method (the handler re-checks method via findHttpMock).
function mockedTargets(httpMocks) {
  const targets = new Set();
  for (const key of Object.keys(httpMocks)) {
    const spaceIdx = key.indexOf(" ");
    if (spaceIdx === -1) continue;
    targets.add(key.slice(spaceIdx + 1));
  }
  return targets;
}

// True when a request URL matches one of the declared mock targets. Accepts
// either a string or a WHATWG URL (Playwright's URL-matcher passes a URL).
function requestTargetsMock(targets, url) {
  const href = typeof url === "string" ? url : url.href;
  return normalizeMockCandidates(href).some((candidate) =>
    targets.has(candidate),
  );
}

async function attachHttpMocks(page, httpMocks) {
  if (!httpMocks || Object.keys(httpMocks).length === 0) return;

  // Intercept ONLY requests whose path matches a declared mock — not every
  // request. A blanket `page.route("**/*")` intercepts the dev server's ESM
  // module/script/style requests too, and routing them through
  // `route.continue()` breaks Vite dev-mode module loading: the lazy app
  // chunks never resolve and the SPA renders blank. Scoping the matcher to
  // mocked targets lets those requests load natively while still mocking the API.
  const targets = mockedTargets(httpMocks);
  await page.route(
    (url) => requestTargetsMock(targets, url),
    async (route) => {
      const mock = findHttpMock(httpMocks, route.request());
      if (!mock) {
        await route.continue();
        return;
      }

      const headers = { ...(mock.headers || {}) };
      let body;
      if (mock.body !== undefined) {
        body =
          typeof mock.body === "string"
            ? mock.body
            : JSON.stringify(mock.body);
        const hasContentType = Object.keys(headers).some(
          (key) => key.toLowerCase() === "content-type",
        );
        if (!hasContentType) {
          headers["content-type"] = "application/json";
        }
      }

      await route.fulfill({
        status: mock.status || 200,
        headers,
        body,
      });
    },
  );

  // Disable the in-page fetch mock by returning an empty active-mocks.json.
  // The HTML injects a script that synchronously loads this file and
  // monkey-patches window.fetch, which would bypass Playwright's route
  // interception. This route is registered AFTER the mock matcher so it takes
  // priority for that path (Playwright uses LIFO ordering for route handlers).
  await page.route("**/active-mocks.json", async (route) => {
    await route.fulfill({
      status: 200,
      headers: { "content-type": "application/json" },
      body: "[]",
    });
  });
}


// True when a console "Failed to load resource" error at `url` corresponds to
// a mock this scenario DECLARED with an error status (>= 400). An intentional
// error-state scenario (e.g. a History tab mocking `GET /api/history` -> 500)
// must not fail its own capture on the console noise its mock deliberately
// produces. Console errors carry no HTTP method, so any method's mock on a
// matching target counts.
function isDeclaredErrorMock(httpMocks, url) {
  const candidates = normalizeMockCandidates(url);
  for (const [key, mock] of Object.entries(httpMocks || {})) {
    const spaceIdx = key.indexOf(" ");
    if (spaceIdx === -1) continue;
    const target = key.slice(spaceIdx + 1);
    if (!candidates.includes(target)) continue;
    if ((mock.status || 200) >= 400) return true;
  }
  return false;
}

module.exports = {
  normalizeMockCandidates,
  findHttpMock,
  mockedTargets,
  requestTargetsMock,
  attachHttpMocks,
  isDeclaredErrorMock,
};
