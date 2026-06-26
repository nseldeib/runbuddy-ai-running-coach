import type { VercelRequest, VercelResponse } from "@vercel/node";
import {
  getHealth,
  upsertHealth,
  deleteHealth,
  incomingWins,
  type HealthRow,
} from "../_lib/account.js";
import { requireUser } from "../_lib/session.js";

// /api/account/health — the OPTIONAL health/activity sync stream.
//
//   GET                        → the stored health row (or { found: false }).
//   PUT    { health, updatedAt }
//                              → last-write-wins upsert (only ever called after
//                                the user consents + enables health sync).
//   DELETE                     → remove the row — the opt-out / "delete my
//                                health data" path.
//
// The user is ALWAYS resolved from the `Authorization: Bearer <session token>`
// via requireUser — never from the request body or query (which would let any
// caller read/delete another user's data). Unauthenticated requests get 401.
//
// Kept in a table distinct from account_prefs so revoking/deleting health sync
// never touches the user's settings, and a settings-only user never has a row
// here at all.

// A derived health snapshot is a handful of numbers; cap the JSON so a hostile
// or buggy client can't push an unbounded blob into the row.
const MAX_HEALTH_BYTES = 64 * 1024;

export default async function handler(req: VercelRequest, res: VercelResponse) {
  try {
    const userId = await requireUser(req);
    if (!userId) {
      res.status(401).json({ error: "unauthorized" });
      return;
    }

    if (req.method === "GET") {
      const row = await getHealth(userId);
      res.status(200).json(row ? { found: true, ...row } : { found: false });
      return;
    }

    if (req.method === "PUT") {
      const body = (req.body ?? {}) as {
        health?: Record<string, unknown>;
        updatedAt?: string;
      };
      const health = body.health;
      const updatedAt = (body.updatedAt ?? "").toString();
      if (!health || typeof health !== "object" || !updatedAt) {
        res.status(400).json({ error: "missing_health_or_updated_at" });
        return;
      }
      if (JSON.stringify(health).length > MAX_HEALTH_BYTES) {
        res.status(413).json({ error: "health_payload_too_large" });
        return;
      }

      const stored = await getHealth(userId);
      if (!incomingWins(stored?.updated_at ?? null, updatedAt)) {
        res.status(200).json({ applied: false, ...(stored as HealthRow) });
        return;
      }
      const row: HealthRow = { user_id: userId, health, updated_at: updatedAt };
      await upsertHealth(row);
      res.status(200).json({ applied: true, ...row });
      return;
    }

    if (req.method === "DELETE") {
      await deleteHealth(userId);
      res.status(200).json({ ok: true });
      return;
    }

    res.status(405).json({ error: "method_not_allowed" });
  } catch (err) {
    console.error("account/health", (err as Error).message); // server-side only — don't leak internals
    res.status(502).json({ error: "health_sync_failed" });
  }
}
