// Server-side session tokens for the account-sync endpoints.
//
// The Apple user identifier (`sub`) is stable but NOT a secret, so it must never
// be accepted from the client as proof of identity. Instead:
//
//   1. At sign-in the app POSTs its Apple identity token to /api/account/session.
//   2. We verify it (see _lib/apple.ts), then mint a high-entropy bearer token,
//      store only its SHA-256 hash keyed to the user, and hand the raw token back.
//   3. The app stores the token and sends it as `Authorization: Bearer <token>`
//      on every account/* request. The server resolves the user from the token —
//      the client never sends a userId.
//
// Required env (shared with Strava/account): SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
//
// Supabase table (create once):
//   create table account_sessions (
//     token_hash text primary key,
//     user_id    text not null,
//     created_at timestamptz default now()
//   );

import { createHash, randomBytes } from "node:crypto";
import type { VercelRequest } from "@vercel/node";
import { env, supabaseHeaders } from "./strava.js";

export function sessionsEndpoint(): string {
  return `${env("SUPABASE_URL")}/rest/v1/account_sessions`;
}

/** SHA-256 hex of a token — only the hash is ever persisted. */
export function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

/**
 * Mint a new session for a verified user: generate a 256-bit token, store its
 * hash, and return the raw token (shown to the client exactly once).
 */
export async function createSession(userId: string): Promise<string> {
  const token = randomBytes(32).toString("base64url");
  const res = await fetch(sessionsEndpoint(), {
    method: "POST",
    headers: { ...supabaseHeaders(), Prefer: "return=minimal" },
    body: JSON.stringify({ token_hash: hashToken(token), user_id: userId }),
  });
  if (!res.ok) throw new Error(`supabase_session_insert_failed:${res.status}`);
  return token;
}

/** Resolve the user id for a bearer token, or null if it isn't a live session. */
export async function userIdForToken(token: string): Promise<string | null> {
  const url = `${sessionsEndpoint()}?token_hash=eq.${encodeURIComponent(hashToken(token))}&select=user_id`;
  const res = await fetch(url, { headers: supabaseHeaders() });
  if (!res.ok) throw new Error(`supabase_session_read_failed:${res.status}`);
  const rows = (await res.json()) as Array<{ user_id: string }>;
  return rows[0]?.user_id ?? null;
}

/** Revoke a session (sign-out / token rotation). Idempotent. */
export async function deleteSession(token: string): Promise<void> {
  const url = `${sessionsEndpoint()}?token_hash=eq.${encodeURIComponent(hashToken(token))}`;
  const res = await fetch(url, { method: "DELETE", headers: supabaseHeaders() });
  if (!res.ok && res.status !== 404) throw new Error(`supabase_session_delete_failed:${res.status}`);
}

/** Extract the raw bearer token from an Authorization header, or null. */
export function bearerToken(req: VercelRequest): string | null {
  const header = req.headers["authorization"];
  const value = Array.isArray(header) ? header[0] : header;
  if (!value) return null;
  const match = /^Bearer\s+(.+)$/i.exec(value.trim());
  return match ? match[1].trim() : null;
}

/**
 * Authenticate a request: returns the verified user id, or null if there's no
 * valid `Authorization: Bearer <session token>`. Handlers map null to 401 and
 * derive the user id ONLY from here — never from the request body or query.
 */
export async function requireUser(req: VercelRequest): Promise<string | null> {
  const token = bearerToken(req);
  if (!token) return null;
  return userIdForToken(token);
}
