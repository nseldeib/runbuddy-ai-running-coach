// Shared Strava + Supabase helpers for the /api/strava/* functions.
//
// Tokens are stored server-side in Supabase keyed by an anonymous device key the
// app generates (no user accounts, no PII). The app never sees the Strava tokens
// — it calls /api/strava/activities and the backend reads/refreshes the token and
// returns mapped runs. Supabase is reached via its PostgREST endpoint with the
// service-role key, so there's no SDK dependency to pull into the function bundle.
//
// Required env (set in Vercel): STRAVA_CLIENT_ID, STRAVA_CLIENT_SECRET,
// SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY. Optional: STRAVA_CALLBACK_BASE
// (defaults to https://otterpace.com).
//
// Supabase table (create once — see docs/strava-and-analytics.md):
//   create table strava_tokens (
//     device_key text primary key,
//     athlete_id bigint,
//     access_token text not null,
//     refresh_token text not null,
//     expires_at bigint not null,
//     updated_at timestamptz default now()
//   );

const STRAVA_TOKEN_URL = "https://www.strava.com/oauth/token";
const STRAVA_API = "https://www.strava.com/api/v3";

export interface TokenRow {
  device_key: string;
  athlete_id: number | null;
  access_token: string;
  refresh_token: string;
  expires_at: number; // unix seconds
}

export function env(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`missing_env:${name}`);
  return v;
}

// The device key is an app-generated, high-entropy (256-bit) random string,
// base64url-encoded. Validate the shape so a malformed/guessy value is rejected
// before it ever reaches Supabase, and so logs/queries can't be poisoned.
const DEVICE_KEY_RE = /^[A-Za-z0-9_-]{16,128}$/;

export function isValidDeviceKey(value: string): boolean {
  return DEVICE_KEY_RE.test(value);
}

/**
 * Read the device key from the `x-device-key` request header. Kept OUT of the
 * URL/query string so it never lands in proxy/CDN access logs (it's a
 * bearer-equivalent secret). Returns "" when missing or malformed.
 */
export function deviceKeyFromHeader(headers: Record<string, unknown> | undefined): string {
  const raw = headers?.["x-device-key"];
  const value = (Array.isArray(raw) ? raw[0] : raw)?.toString().trim() ?? "";
  return isValidDeviceKey(value) ? value : "";
}

export function supabaseHeaders(): Record<string, string> {
  const key = env("SUPABASE_SERVICE_ROLE_KEY");
  return {
    apikey: key,
    Authorization: `Bearer ${key}`,
    "Content-Type": "application/json",
  };
}

export function tokensEndpoint(): string {
  return `${env("SUPABASE_URL")}/rest/v1/strava_tokens`;
}

export async function getToken(deviceKey: string): Promise<TokenRow | null> {
  const url = `${tokensEndpoint()}?device_key=eq.${encodeURIComponent(deviceKey)}&select=*`;
  const res = await fetch(url, { headers: supabaseHeaders() });
  if (!res.ok) throw new Error(`supabase_read_failed:${res.status}`);
  const rows = (await res.json()) as TokenRow[];
  return rows[0] ?? null;
}

export async function upsertToken(row: TokenRow): Promise<void> {
  const res = await fetch(tokensEndpoint(), {
    method: "POST",
    headers: { ...supabaseHeaders(), Prefer: "resolution=merge-duplicates,return=minimal" },
    body: JSON.stringify({ ...row, updated_at: new Date().toISOString() }),
  });
  if (!res.ok) throw new Error(`supabase_upsert_failed:${res.status}`);
}

export async function deleteToken(deviceKey: string): Promise<void> {
  const url = `${tokensEndpoint()}?device_key=eq.${encodeURIComponent(deviceKey)}`;
  const res = await fetch(url, { method: "DELETE", headers: supabaseHeaders() });
  if (!res.ok && res.status !== 404) throw new Error(`supabase_delete_failed:${res.status}`);
}

interface StravaTokenResponse {
  access_token: string;
  refresh_token: string;
  expires_at: number;
  athlete?: { id?: number; firstname?: string };
}

/** Exchange an authorization code for tokens (uses the client secret). */
export async function exchangeCode(code: string): Promise<StravaTokenResponse> {
  const res = await fetch(STRAVA_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      client_id: env("STRAVA_CLIENT_ID"),
      client_secret: env("STRAVA_CLIENT_SECRET"),
      code,
      grant_type: "authorization_code",
    }),
  });
  if (!res.ok) throw new Error(`strava_exchange_failed:${res.status}`);
  return (await res.json()) as StravaTokenResponse;
}

/** Return a valid access token for the device, refreshing + persisting if expired. */
export async function freshAccessToken(row: TokenRow): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (row.expires_at - 60 > now) return row.access_token; // still valid

  const res = await fetch(STRAVA_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      client_id: env("STRAVA_CLIENT_ID"),
      client_secret: env("STRAVA_CLIENT_SECRET"),
      grant_type: "refresh_token",
      refresh_token: row.refresh_token,
    }),
  });
  if (!res.ok) throw new Error(`strava_refresh_failed:${res.status}`);
  const refreshed = (await res.json()) as StravaTokenResponse;
  await upsertToken({
    device_key: row.device_key,
    athlete_id: row.athlete_id,
    access_token: refreshed.access_token,
    refresh_token: refreshed.refresh_token,
    expires_at: refreshed.expires_at,
  });
  return refreshed.access_token;
}

interface StravaActivity {
  id: number;
  name: string;
  sport_type: string;
  start_date_local: string;
  distance: number;        // meters
  moving_time: number;     // seconds
  average_speed: number;   // m/s
  total_elevation_gain: number;
}

/** Fetch recent activities and map them to the app's LatestWorkout shape. */
export async function fetchMappedActivities(accessToken: string, perPage = 30): Promise<MappedWorkout[]> {
  const res = await fetch(`${STRAVA_API}/athlete/activities?per_page=${perPage}`, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) throw new Error(`strava_activities_failed:${res.status}`);
  const acts = (await res.json()) as StravaActivity[];
  return acts.map(mapActivity).filter((w): w is MappedWorkout => w !== null);
}

export interface MappedWorkout {
  id: string;
  type: string;          // "run", "yoga", ...
  distanceMiles: number;
  durationMinutes: number;
  pace: string;          // "mm:ss/mi" or "" when no distance
  date: string;          // YYYY-MM-DD
  source: string;        // "strava"
}

const METERS_PER_MILE = 1609.344;

export function mapActivity(a: StravaActivity): MappedWorkout | null {
  // Skip anything without a usable date — an empty/garbage date breaks the app's
  // week-grouping and newest-first sorting downstream.
  const date = (a.start_date_local || "").slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return null;
  const miles = a.distance > 0 ? a.distance / METERS_PER_MILE : 0;
  return {
    id: String(a.id),
    type: (a.sport_type || "workout").toLowerCase(),
    distanceMiles: round1(miles),
    durationMinutes: Math.round(a.moving_time / 60),
    pace: a.average_speed > 0 ? pacePerMile(a.average_speed) : "",
    date,
    source: "strava",
  };
}

export function pacePerMile(metersPerSecond: number): string {
  const secPerMile = METERS_PER_MILE / metersPerSecond;
  const m = Math.floor(secPerMile / 60);
  const s = Math.round(secPerMile % 60);
  return `${m}:${String(s).padStart(2, "0")}/mi`;
}

export function round1(n: number): number {
  return Math.round(n * 10) / 10;
}
