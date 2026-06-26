import type { VercelRequest } from "@vercel/node";

// Best-effort, in-memory fixed-window rate limiter.
//
// IMPORTANT: this is per-warm-instance, not global. On Vercel each concurrent
// lambda instance keeps its own map, so under heavy load the effective limit is
// (limit × live instances). It throttles a single client hammering one warm
// instance — a useful first layer against trivial floods and accidental retry
// storms — but it is NOT a hard quota. For a hard, shared limit, back this with
// an external store (e.g. Upstash/Redis or a Supabase counter). Documented in
// SECURITY.md so the guarantee isn't overstated.

interface Window {
  count: number;
  resetAt: number; // epoch ms
}

const buckets = new Map<string, Window>();

/** Client IP from Vercel's forwarding headers, falling back to the socket. */
export function clientIp(req: VercelRequest): string {
  const fwd = req.headers["x-forwarded-for"];
  const value = Array.isArray(fwd) ? fwd[0] : fwd;
  if (value) return value.split(",")[0]!.trim();
  return req.socket?.remoteAddress ?? "unknown";
}

/**
 * Returns true if the request is allowed, false if it exceeds `limit` requests
 * per `windowMs` for this `key` on this instance. Opportunistically evicts
 * expired windows so the map can't grow unbounded.
 */
export function allow(key: string, limit: number, windowMs: number, now: number): boolean {
  const existing = buckets.get(key);
  if (!existing || now >= existing.resetAt) {
    buckets.set(key, { count: 1, resetAt: now + windowMs });
    if (buckets.size > 10000) {
      for (const [k, w] of buckets) if (now >= w.resetAt) buckets.delete(k);
    }
    return true;
  }
  if (existing.count >= limit) return false;
  existing.count += 1;
  return true;
}
