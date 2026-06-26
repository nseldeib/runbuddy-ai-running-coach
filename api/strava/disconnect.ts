import type { VercelRequest, VercelResponse } from "@vercel/node";
import { deleteToken, isValidDeviceKey } from "../_lib/strava.js";

// POST { deviceKey } — forget this device's Strava tokens (server-side delete).
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }
  const body = (req.body ?? {}) as { deviceKey?: string };
  const deviceKey = (body.deviceKey ?? "").toString();
  if (!isValidDeviceKey(deviceKey)) {
    res.status(400).json({ error: "missing_device_key" });
    return;
  }
  try {
    await deleteToken(deviceKey);
    res.status(200).json({ ok: true });
  } catch (err) {
    console.error("strava/disconnect", (err as Error).message); // server-side only
    res.status(502).json({ error: "disconnect_failed" });
  }
}
