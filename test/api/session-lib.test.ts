import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import {
  sessionsEndpoint,
  hashToken,
  createSession,
  userIdForToken,
  deleteSession,
  bearerToken,
  requireUser,
} from "../../api/_lib/session.ts";

// Unit tests for the shared account-session helpers. Network calls go through a
// stubbed global `fetch`, so no real Supabase request is ever made; the pure
// helpers (hashToken, bearerToken, sessionsEndpoint) are asserted directly.

const ENV = {
  SUPABASE_URL: "https://db.example.co",
  SUPABASE_SERVICE_ROLE_KEY: "service-role",
};

function fetchReturning(status: number, body: unknown) {
  return vi.fn().mockResolvedValue({
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function req(headers: Record<string, unknown>): any {
  return { headers };
}

beforeEach(() => {
  for (const [k, v] of Object.entries(ENV)) process.env[k] = v;
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

// MARK: - pure helpers

describe("sessionsEndpoint", () => {
  it("targets the account_sessions REST table on the configured Supabase URL", () => {
    expect(sessionsEndpoint()).toBe("https://db.example.co/rest/v1/account_sessions");
  });
});

describe("hashToken", () => {
  it("is the lowercase SHA-256 hex of the token, never the raw token", () => {
    // SHA-256("hello") — stable, well-known vector.
    expect(hashToken("hello")).toBe(
      "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
    );
    expect(hashToken("hello")).not.toContain("hello");
  });

  it("is deterministic and differs for different inputs", () => {
    expect(hashToken("a")).toBe(hashToken("a"));
    expect(hashToken("a")).not.toBe(hashToken("b"));
  });
});

describe("bearerToken", () => {
  it("extracts the raw token from an Authorization: Bearer header", () => {
    expect(bearerToken(req({ authorization: "Bearer abc123" }))).toBe("abc123");
  });

  it("is case-insensitive on the scheme and trims surrounding space", () => {
    expect(bearerToken(req({ authorization: "  bearer   tok  " }))).toBe("tok");
  });

  it("collapses an array-valued header to its first entry", () => {
    expect(bearerToken(req({ authorization: ["Bearer first", "Bearer second"] }))).toBe("first");
  });

  it("returns null when the header is missing or not a bearer scheme", () => {
    expect(bearerToken(req({}))).toBeNull();
    expect(bearerToken(req({ authorization: "Basic abc" }))).toBeNull();
  });
});

// MARK: - Supabase-backed helpers (stubbed fetch)

describe("createSession", () => {
  it("POSTs a token hash for the user and returns the raw token", async () => {
    const fetchMock = fetchReturning(201, null);
    vi.stubGlobal("fetch", fetchMock);
    const token = await createSession("u1");
    expect(typeof token).toBe("string");
    expect(token.length).toBeGreaterThan(0);
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe(sessionsEndpoint());
    expect(init.method).toBe("POST");
    const sent = JSON.parse(init.body);
    expect(sent.user_id).toBe("u1");
    // Only the hash of the returned token is persisted — never the raw token.
    expect(sent.token_hash).toBe(hashToken(token));
    expect(sent.token_hash).not.toBe(token);
  });

  it("throws when the insert fails", async () => {
    vi.stubGlobal("fetch", fetchReturning(500, null));
    await expect(createSession("u1")).rejects.toThrow(/supabase_session_insert_failed:500/);
  });
});

describe("userIdForToken", () => {
  it("queries by token hash and returns the stored user id", async () => {
    const fetchMock = fetchReturning(200, [{ user_id: "u9" }]);
    vi.stubGlobal("fetch", fetchMock);
    expect(await userIdForToken("raw")).toBe("u9");
    const [url] = fetchMock.mock.calls[0];
    expect(url).toContain(`token_hash=eq.${hashToken("raw")}`);
  });

  it("returns null when no session matches", async () => {
    vi.stubGlobal("fetch", fetchReturning(200, []));
    expect(await userIdForToken("raw")).toBeNull();
  });

  it("throws on a failed read", async () => {
    vi.stubGlobal("fetch", fetchReturning(500, null));
    await expect(userIdForToken("raw")).rejects.toThrow(/supabase_session_read_failed:500/);
  });
});

describe("deleteSession", () => {
  it("DELETEs the row keyed by token hash", async () => {
    const fetchMock = fetchReturning(204, null);
    vi.stubGlobal("fetch", fetchMock);
    await deleteSession("raw");
    const [url, init] = fetchMock.mock.calls[0];
    expect(init.method).toBe("DELETE");
    expect(url).toContain(`token_hash=eq.${hashToken("raw")}`);
  });

  it("is idempotent: a 404 is not an error", async () => {
    vi.stubGlobal("fetch", fetchReturning(404, null));
    await expect(deleteSession("raw")).resolves.toBeUndefined();
  });

  it("throws on other failures", async () => {
    vi.stubGlobal("fetch", fetchReturning(500, null));
    await expect(deleteSession("raw")).rejects.toThrow(/supabase_session_delete_failed:500/);
  });
});

describe("requireUser", () => {
  it("resolves the user id from a valid bearer token", async () => {
    vi.stubGlobal("fetch", fetchReturning(200, [{ user_id: "u7" }]));
    expect(await requireUser(req({ authorization: "Bearer good" }))).toBe("u7");
  });

  it("returns null without an Authorization header (no network call)", async () => {
    const fetchMock = fetchReturning(200, []);
    vi.stubGlobal("fetch", fetchMock);
    expect(await requireUser(req({}))).toBeNull();
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
