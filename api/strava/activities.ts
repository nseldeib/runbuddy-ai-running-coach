import type { VercelRequest, VercelResponse } from "@vercel/node";
import { getToken, freshAccessToken, fetchMappedActivities, deviceKeyFromHeader } from "../_lib/strava.js";

// GET (x-device-key header) — read the device's Strava token from Supabase
// (refreshing it server-side if expired), fetch recent activities, and return
// them mapped to the app's workout shape. The app never handles the Strava
// access token. The device key rides in a header, never the query string, so it
// stays out of access logs.
export default async function handler(req: VercelRequest, res: VercelResponse) {
  const deviceKey = deviceKeyFromHeader(req.headers);
  if (!deviceKey) {
    res.status(400).json({ error: "missing_device_key" });
    return;
  }

  try {
    const row = await getToken(deviceKey);
    if (!row) {
      res.status(200).json({ connected: false, activities: [] });
      return;
    }
    const accessToken = await freshAccessToken(row);
    const activities = await fetchMappedActivities(accessToken);
    res.status(200).json({ connected: true, activities });
  } catch (err) {
    console.error("strava/activities", (err as Error).message); // server-side only
    res.status(502).json({ error: "activities_failed" });
  }
}
