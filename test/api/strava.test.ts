import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import {
  env,
  supabaseHeaders,
  tokensEndpoint,
  getToken,
  upsertToken,
  deleteToken,
  exchangeCode,
  freshAccessToken,
  fetchMappedActivities,
  mapActivity,
  pacePerMile,
  round1,
  type TokenRow,
} from "../../api/_lib/strava.ts";

// Unit tests for the shared Strava + Supabase helpers. Network calls are
// exercised against a stubbed global `fetch`, so no real Strava/Supabase
// request is ever made; pure helpers are tested directly.

const ENV = {
  STRAVA_CLIENT_ID: "cid",
  STRAVA_CLIENT_SECRET: "secret",
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

function sampleRow(overrides: Partial<TokenRow> = {}): TokenRow {
  return {
    device_key: "dev-1",
    athlete_id: 42,
    access_token: "acc",
    refresh_token: "ref",
    expires_at: 0,
    ...overrides,
  };
}

beforeEach(() => {
  for (const [k, v] of Object.entries(ENV)) process.env[k] = v;
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

// MARK: - pure helpers

describe("round1", () => {
  // Rounds to a single decimal place.
  it("rounds to one decimal", () => {
    expect(round1(4.249)).toBe(4.2);
    expect(round1(4.25)).toBe(4.3);
    expect(round1(0)).toBe(0);
  });
});

describe("pacePerMile", () => {
  // Converts m/s to a mm:ss/mi pace string, zero-padding the seconds.
  it("formats pace with padded seconds", () => {
    // 1609.344 m/mi ÷ 2.68 m/s ≈ 600.5 s/mi → 10:00/mi
    expect(pacePerMile(2.6822)).toBe("10:00/mi");
  });
  it("pads single-digit seconds", () => {
    const pace = pacePerMile(3.0);
    expect(pace).toMatch(/^\d+:\d{2}\/mi$/);
  });
});

describe("mapActivity", () => {
  const base = {
    id: 99,
    name: "Morning Run",
    sport_type: "Run",
    start_date_local: "2026-06-21T07:15:00Z",
    distance: 6759.2, // ~4.2 mi
    moving_time: 2580, // 43 min
    average_speed: 2.6822,
    total_elevation_gain: 30,
  };

  // A well-formed activity maps to the app's MappedWorkout shape.
  it("maps a valid activity", () => {
    const w = mapActivity(base)!;
    expect(w).not.toBeNull();
    expect(w.id).toBe("99");
    expect(w.type).toBe("run");
    expect(w.distanceMiles).toBe(4.2);
    expect(w.durationMinutes).toBe(43);
    expect(w.pace).toBe("10:00/mi");
    expect(w.date).toBe("2026-06-21");
    expect(w.source).toBe("strava");
  });

  // An activity whose date is missing/garbage is skipped (returns null).
  it("returns null for a bad date", () => {
    expect(mapActivity({ ...base, start_date_local: "" })).toBeNull();
    expect(mapActivity({ ...base, start_date_local: "not-a-date" })).toBeNull();
  });

  // A zero-distance activity yields zero miles and an empty pace.
  it("handles zero distance", () => {
    const w = mapActivity({ ...base, distance: 0, average_speed: 0 })!;
    expect(w.distanceMiles).toBe(0);
    expect(w.pace).toBe("");
  });

  // Falls back to a generic type when sport_type is absent.
  it("defaults the type when sport_type is empty", () => {
    const w = mapActivity({ ...base, sport_type: "" })!;
    expect(w.type).toBe("workout");
  });
});

// MARK: - env / header helpers

describe("env", () => {
  // Returns the value when set, throws a typed error when missing.
  it("returns a set var", () => {
    expect(env("STRAVA_CLIENT_ID")).toBe("cid");
  });
  it("throws missing_env for an unset var", () => {
    delete process.env.NOPE;
    expect(() => env("NOPE")).toThrow("missing_env:NOPE");
  });
});

describe("supabaseHeaders", () => {
  // Builds apikey + bearer headers from the service-role key.
  it("includes the service-role key", () => {
    const h = supabaseHeaders();
    expect(h.apikey).toBe("service-role");
    expect(h.Authorization).toBe("Bearer service-role");
    expect(h["Content-Type"]).toBe("application/json");
  });
});

describe("tokensEndpoint", () => {
  // Builds the PostgREST table URL from SUPABASE_URL.
  it("points at the strava_tokens table", () => {
    expect(tokensEndpoint()).toBe("https://db.example.co/rest/v1/strava_tokens");
  });
});

// MARK: - Supabase I/O

describe("getToken", () => {
  // Returns the first matching row, or null when none exist.
  it("returns the row when present", async () => {
    vi.stubGlobal("fetch", fetchReturning(200, [sampleRow()]));
    const row = await getToken("dev-1");
    expect(row?.device_key).toBe("dev-1");
  });
  it("returns null when no rows", async () => {
    vi.stubGlobal("fetch", fetchReturning(200, []));
    expect(await getToken("dev-x")).toBeNull();
  });
  // A non-OK read surfaces as a typed error.
  it("throws on a failed read", async () => {
    vi.stubGlobal("fetch", fetchReturning(500, {}));
    await expect(getToken("dev-1")).rejects.toThrow("supabase_read_failed:500");
  });
});

describe("upsertToken", () => {
  // POSTs the row; throws on a non-OK response.
  it("posts to the tokens endpoint", async () => {
    const f = fetchReturning(201, {});
    vi.stubGlobal("fetch", f);
    await upsertToken(sampleRow());
    expect(f).toHaveBeenCalledOnce();
    const [, init] = f.mock.calls[0];
    expect(init.method).toBe("POST");
  });
  it("throws on a failed upsert", async () => {
    vi.stubGlobal("fetch", fetchReturning(400, {}));
    await expect(upsertToken(sampleRow())).rejects.toThrow("supabase_upsert_failed:400");
  });
});

describe("deleteToken", () => {
  // Deletes the row; tolerates 404 (already gone); throws on other errors.
  it("deletes successfully", async () => {
    vi.stubGlobal("fetch", fetchReturning(204, {}));
    await expect(deleteToken("dev-1")).resolves.toBeUndefined();
  });
  it("tolerates a 404", async () => {
    vi.stubGlobal("fetch", fetchReturning(404, {}));
    await expect(deleteToken("dev-1")).resolves.toBeUndefined();
  });
  it("throws on a 500", async () => {
    vi.stubGlobal("fetch", fetchReturning(500, {}));
    await expect(deleteToken("dev-1")).rejects.toThrow("supabase_delete_failed:500");
  });
});

// MARK: - Strava OAuth I/O

describe("exchangeCode", () => {
  // Exchanges an auth code for tokens; throws on a non-OK response.
  it("returns the token response", async () => {
    vi.stubGlobal("fetch", fetchReturning(200, { access_token: "a", refresh_token: "r", expires_at: 123 }));
    const tok = await exchangeCode("the-code");
    expect(tok.access_token).toBe("a");
  });
  it("throws on a failed exchange", async () => {
    vi.stubGlobal("fetch", fetchReturning(400, {}));
    await expect(exchangeCode("bad")).rejects.toThrow("strava_exchange_failed:400");
  });
});

describe("freshAccessToken", () => {
  // A still-valid token is returned without any network call.
  it("returns the existing token when not near expiry", async () => {
    const f = vi.fn();
    vi.stubGlobal("fetch", f);
    const future = Math.floor(Date.now() / 1000) + 3600;
    const token = await freshAccessToken(sampleRow({ expires_at: future, access_token: "still-good" }));
    expect(token).toBe("still-good");
    expect(f).not.toHaveBeenCalled();
  });

  // An expired token is refreshed against Strava and the new token persisted.
  it("refreshes and persists an expired token", async () => {
    const past = Math.floor(Date.now() / 1000) - 10;
    const f = vi
      .fn()
      // first call: refresh at Strava
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({ access_token: "new-acc", refresh_token: "new-ref", expires_at: past + 7200 }),
      })
      // second call: upsert into Supabase
      .mockResolvedValueOnce({ ok: true, status: 204, json: async () => ({}) });
    vi.stubGlobal("fetch", f);
    const token = await freshAccessToken(sampleRow({ expires_at: past }));
    expect(token).toBe("new-acc");
    expect(f).toHaveBeenCalledTimes(2);
  });
});

describe("fetchMappedActivities", () => {
  // Maps Strava activities and filters out any that fail validation (bad date).
  it("maps and filters activities", async () => {
    const acts = [
      { id: 1, name: "Run", sport_type: "Run", start_date_local: "2026-06-20T07:00:00Z", distance: 1609.344, moving_time: 600, average_speed: 2.6822, total_elevation_gain: 0 },
      { id: 2, name: "Bad", sport_type: "Run", start_date_local: "", distance: 1000, moving_time: 300, average_speed: 3, total_elevation_gain: 0 },
    ];
    vi.stubGlobal("fetch", fetchReturning(200, acts));
    const mapped = await fetchMappedActivities("token");
    expect(mapped).toHaveLength(1);
    expect(mapped[0].id).toBe("1");
  });
  it("throws on a failed activities fetch", async () => {
    vi.stubGlobal("fetch", fetchReturning(401, {}));
    await expect(fetchMappedActivities("token")).rejects.toThrow("strava_activities_failed:401");
  });
});
