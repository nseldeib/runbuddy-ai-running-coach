import type { VercelRequest, VercelResponse } from "@vercel/node";
import { isValidDeviceKey } from "../_lib/strava.js";

// Strava redirects the browser here after the user approves (Authorization
// Callback Domain = otterpace.com). We bounce straight back into the app's
// custom scheme so ASWebAuthenticationSession can capture the code. The device
// key rides along in `state` so the exchange step knows whose tokens to store.
//
// Every reflected value is validated against its expected shape before it goes
// into the redirect URL, so a crafted callback can't inject arbitrary query
// params into the app's `otterpace://strava-callback` handler. The redirect host
// is a fixed app scheme — never derived from input.
const CODE_RE = /^[A-Za-z0-9]{1,256}$/;        // Strava authorization codes are hex-ish
const ERROR_RE = /^[a-z_]{1,64}$/;             // OAuth error codes, e.g. access_denied

export default function handler(req: VercelRequest, res: VercelResponse) {
  const { code, state, error } = req.query as Record<string, string | undefined>;
  const params = new URLSearchParams();

  if (error && ERROR_RE.test(error)) params.set("error", error);
  else if (code && CODE_RE.test(code)) params.set("code", code);
  else params.set("error", "invalid_callback");

  if (state && isValidDeviceKey(state)) params.set("state", state);

  res.statusCode = 302;
  res.setHeader("Location", `otterpace://strava-callback?${params.toString()}`);
  res.end();
}
