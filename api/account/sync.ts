import type { VercelRequest, VercelResponse } from "@vercel/node";
import {
  getPrefs,
  upsertPrefs,
  prefsContainHealthFields,
  incomingWins,
  type PrefsRow,
} from "../_lib/account.js";
import { requireUser } from "../_lib/session.js";

// /api/account/sync — the settings/preferences sync stream for a signed-in user.
//
//   GET                       → the stored prefs row (or { found: false }).
//   PUT  { prefs, updatedAt }  → last-write-wins upsert. If the stored row is
//                               newer, it wins and is returned unchanged.
//
// The user is resolved from the `Authorization: Bearer <session token>` via
// requireUser — never from the request body or query. Unauthenticated → 401.
//
// This endpoint carries ONLY settings/preferences. A payload containing any
// health field is rejected (defense in depth) so a settings-only user can never
// leak health data into the wrong table.

// Preferences are a tiny key/value bag (step goal, reminder prefs); cap the JSON.
const MAX_PREFS_BYTES = 16 * 1024;

export default async function handler(req: VercelRequest, res: VercelResponse) {
  try {
    const userId = await requireUser(req);
    if (!userId) {
      res.status(401).json({ error: "unauthorized" });
      return;
    }

    if (req.method === "GET") {
      const row = await getPrefs(userId);
      res.status(200).json(row ? { found: true, ...row } : { found: false });
      return;
    }

    if (req.method === "PUT") {
      const body = (req.body ?? {}) as {
        prefs?: Record<string, unknown>;
        updatedAt?: string;
      };
      const prefs = body.prefs;
      const updatedAt = (body.updatedAt ?? "").toString();
      if (!prefs || typeof prefs !== "object" || !updatedAt) {
        res.status(400).json({ error: "missing_prefs_or_updated_at" });
        return;
      }
      if (JSON.stringify(prefs).length > MAX_PREFS_BYTES) {
        res.status(413).json({ error: "prefs_payload_too_large" });
        return;
      }
      if (prefsContainHealthFields(prefs)) {
        res.status(400).json({ error: "health_fields_not_allowed_on_prefs" });
        return;
      }

      const stored = await getPrefs(userId);
      if (!incomingWins(stored?.updated_at ?? null, updatedAt)) {
        // Remote is newer (or equal) — it wins; hand the client the winning row.
        res.status(200).json({ applied: false, ...(stored as PrefsRow) });
        return;
      }
      const row: PrefsRow = { user_id: userId, prefs, updated_at: updatedAt };
      await upsertPrefs(row);
      res.status(200).json({ applied: true, ...row });
      return;
    }

    res.status(405).json({ error: "method_not_allowed" });
  } catch (err) {
    console.error("account/sync", (err as Error).message); // server-side only — don't leak internals
    res.status(502).json({ error: "sync_failed" });
  }
}
