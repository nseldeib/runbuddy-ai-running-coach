import type { VercelRequest, VercelResponse } from "@vercel/node";
import { exchangeCode, upsertToken, isValidDeviceKey } from "../_lib/strava.js";

// POST { code, deviceKey } — exchange the OAuth code for tokens (server-side,
// using the client secret) and store them in Supabase keyed by the device key.
// Returns only a success flag + athlete first name; the tokens never go to the app.
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }
  const body = (req.body ?? {}) as { code?: string; deviceKey?: string };
  const code = (body.code ?? "").toString();
  const deviceKey = (body.deviceKey ?? "").toString();
  if (!code || !isValidDeviceKey(deviceKey)) {
    res.status(400).json({ error: "missing_code_or_device_key" });
    return;
  }

  try {
    const tok = await exchangeCode(code);
    await upsertToken({
      device_key: deviceKey,
      athlete_id: tok.athlete?.id ?? null,
      access_token: tok.access_token,
      refresh_token: tok.refresh_token,
      expires_at: tok.expires_at,
    });
    res.status(200).json({ connected: true, athleteName: tok.athlete?.firstname ?? null });
  } catch (err) {
    console.error("strava/exchange", (err as Error).message); // server-side only — don't leak internals to the client
    res.status(502).json({ error: "exchange_failed" });
  }
}
