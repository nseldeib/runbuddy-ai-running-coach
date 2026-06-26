import { describe, it, expect, vi, beforeEach } from "vitest";

// The four /api/strava/* handlers are thin glue over the _lib/strava helpers.
// Mock that module so we assert each handler's request validation, status
// codes, and response shaping without any network call.
const lib = vi.hoisted(() => ({
  getToken: vi.fn(),
  freshAccessToken: vi.fn(),
  fetchMappedActivities: vi.fn(),
  deleteToken: vi.fn(),
  exchangeCode: vi.fn(),
  upsertToken: vi.fn(),
}));
// Mock the network helpers but keep the PURE helpers (isValidDeviceKey,
// deviceKeyFromHeader) real so the handlers' validation is exercised for real.
vi.mock("../../api/_lib/strava.ts", async (importActual) => ({
  ...(await importActual<typeof import("../../api/_lib/strava.ts")>()),
  ...lib,
}));

// A well-formed device key: high-entropy, base64url, ≥16 chars.
const KEY = "dev_key_abcdef1234567890";

import activities from "../../api/strava/activities.ts";
import callback from "../../api/strava/callback.ts";
import disconnect from "../../api/strava/disconnect.ts";
import exchange from "../../api/strava/exchange.ts";

function makeRes() {
  return {
    statusCode: 0,
    body: undefined as unknown,
    headers: {} as Record<string, string>,
    ended: false,
    status(c: number) {
      this.statusCode = c;
      return this;
    },
    json(b: unknown) {
      this.body = b;
      return this;
    },
    setHeader(k: string, v: string) {
      this.headers[k] = v;
    },
    end() {
      this.ended = true;
    },
  };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function run(handler: any, req: any) {
  const res = makeRes();
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return Promise.resolve(handler(req as any, res as any)).then(() => res);
}

beforeEach(() => {
  vi.clearAllMocks();
  vi.spyOn(console, "error").mockImplementation(() => {});
});

describe("strava/activities", () => {
  // A request without a device-key header is a 400.
  it("400s without a device key", async () => {
    const res = await run(activities, { headers: {} });
    expect(res.statusCode).toBe(400);
  });

  // A malformed (too short) device key is rejected before any lookup.
  it("400s on a malformed device key", async () => {
    const res = await run(activities, { headers: { "x-device-key": "short" } });
    expect(res.statusCode).toBe(400);
    expect(lib.getToken).not.toHaveBeenCalled();
  });

  // No stored token → not-connected with an empty list (not an error).
  it("reports not-connected when no token", async () => {
    lib.getToken.mockResolvedValue(null);
    const res = await run(activities, { headers: { "x-device-key": KEY } });
    expect(res.statusCode).toBe(200);
    expect(res.body).toEqual({ connected: false, activities: [] });
  });

  // With a token, it refreshes, fetches, and returns mapped activities.
  it("returns mapped activities when connected", async () => {
    lib.getToken.mockResolvedValue({ device_key: KEY });
    lib.freshAccessToken.mockResolvedValue("acc");
    lib.fetchMappedActivities.mockResolvedValue([{ id: "1" }]);
    const res = await run(activities, { headers: { "x-device-key": KEY } });
    expect(res.statusCode).toBe(200);
    expect(res.body).toEqual({ connected: true, activities: [{ id: "1" }] });
  });

  // A thrown helper error becomes a generic 502 (details logged server-side only).
  it("502s on a helper error", async () => {
    lib.getToken.mockRejectedValue(new Error("supabase down"));
    const res = await run(activities, { headers: { "x-device-key": KEY } });
    expect(res.statusCode).toBe(502);
  });
});

describe("strava/callback", () => {
  // A successful auth bounces back into the app scheme with code + state.
  it("redirects with the code and state", async () => {
    const res = await run(callback, { query: { code: "abc", state: KEY } });
    expect(res.statusCode).toBe(302);
    expect(res.headers.Location).toContain("otterpace://strava-callback?");
    expect(res.headers.Location).toContain("code=abc");
    expect(res.headers.Location).toContain(`state=${KEY}`);
  });

  // An OAuth error is forwarded in the redirect.
  it("forwards an oauth error", async () => {
    const res = await run(callback, { query: { error: "access_denied", state: KEY } });
    expect(res.headers.Location).toContain("error=access_denied");
  });

  // A malformed code / injection attempt is replaced with a safe error, and a
  // malformed state is dropped entirely (no arbitrary params reach the app).
  it("sanitizes a malformed code and drops a bad state", async () => {
    const res = await run(callback, { query: { code: "abc&evil=1", state: "../../x" } });
    expect(res.headers.Location).toContain("error=invalid_callback");
    expect(res.headers.Location).not.toContain("evil");
    expect(res.headers.Location).not.toContain("state=");
  });

  // No code and no error becomes an explicit invalid_callback error redirect.
  it("redirects with an error when nothing usable", async () => {
    const res = await run(callback, { query: {} });
    expect(res.headers.Location).toContain("error=invalid_callback");
  });
});

describe("strava/disconnect", () => {
  // Only POST is allowed.
  it("405s on non-POST", async () => {
    const res = await run(disconnect, { method: "GET", body: {} });
    expect(res.statusCode).toBe(405);
  });

  // Missing device key is a 400.
  it("400s without a device key", async () => {
    const res = await run(disconnect, { method: "POST", body: {} });
    expect(res.statusCode).toBe(400);
  });

  // A valid request deletes the token and returns ok.
  it("deletes the token", async () => {
    lib.deleteToken.mockResolvedValue(undefined);
    const res = await run(disconnect, { method: "POST", body: { deviceKey: KEY } });
    expect(res.statusCode).toBe(200);
    expect(res.body).toEqual({ ok: true });
    expect(lib.deleteToken).toHaveBeenCalledWith(KEY);
  });

  // A delete failure is a generic 502.
  it("502s on a delete error", async () => {
    lib.deleteToken.mockRejectedValue(new Error("nope"));
    const res = await run(disconnect, { method: "POST", body: { deviceKey: KEY } });
    expect(res.statusCode).toBe(502);
  });
});

describe("strava/exchange", () => {
  // Only POST is allowed.
  it("405s on non-POST", async () => {
    const res = await run(exchange, { method: "GET", body: {} });
    expect(res.statusCode).toBe(405);
  });

  // Both code and device key are required.
  it("400s without code or device key", async () => {
    const res = await run(exchange, { method: "POST", body: { code: "only-code" } });
    expect(res.statusCode).toBe(400);
  });

  // A malformed device key is rejected before any exchange.
  it("400s on a malformed device key", async () => {
    const res = await run(exchange, { method: "POST", body: { code: "c", deviceKey: "dev" } });
    expect(res.statusCode).toBe(400);
    expect(lib.exchangeCode).not.toHaveBeenCalled();
  });

  // A valid exchange stores tokens and returns the athlete first name only.
  it("exchanges and stores tokens", async () => {
    lib.exchangeCode.mockResolvedValue({
      access_token: "a",
      refresh_token: "r",
      expires_at: 123,
      athlete: { id: 7, firstname: "Sam" },
    });
    lib.upsertToken.mockResolvedValue(undefined);
    const res = await run(exchange, { method: "POST", body: { code: "c", deviceKey: KEY } });
    expect(res.statusCode).toBe(200);
    expect(res.body).toEqual({ connected: true, athleteName: "Sam" });
    expect(lib.upsertToken).toHaveBeenCalledOnce();
  });

  // A failed exchange is a generic 502.
  it("502s on an exchange error", async () => {
    lib.exchangeCode.mockRejectedValue(new Error("bad code"));
    const res = await run(exchange, { method: "POST", body: { code: "c", deviceKey: KEY } });
    expect(res.statusCode).toBe(502);
  });
});
