import type { VercelRequest, VercelResponse } from "@vercel/node";
import { verifyAppleIdentityToken } from "../_lib/apple.js";
import { createSession, deleteSession, bearerToken } from "../_lib/session.js";

// /api/account/session — establish or revoke a backend session.
//
//   POST { identityToken }    → verify the Apple identity token, mint a bearer
//                               session token, return { token }. Called once at
//                               sign-in; the app stores the token in the Keychain.
//   DELETE  (Bearer <token>)  → revoke the current session (sign-out).
//
// This is the ONLY place a client-supplied identity is accepted, and only as a
// signed Apple token we verify — never a bare userId. Everything else
// authenticates with the minted bearer token (see _lib/session.ts).
//
// An Apple identity token is a JWS; even a large one is well under a few KB.
const MAX_IDENTITY_TOKEN_LEN = 8192;

export default async function handler(req: VercelRequest, res: VercelResponse) {
  try {
    if (req.method === "POST") {
      const body = (req.body ?? {}) as { identityToken?: unknown };
      const idToken = typeof body.identityToken === "string" ? body.identityToken : "";
      if (!idToken || idToken.length > MAX_IDENTITY_TOKEN_LEN) {
        res.status(400).json({ error: "missing_or_oversized_identity_token" });
        return;
      }

      let userId: string;
      try {
        userId = await verifyAppleIdentityToken(idToken);
      } catch {
        // Bad signature / issuer / audience / expiry — never reveal which.
        res.status(401).json({ error: "invalid_identity_token" });
        return;
      }

      const token = await createSession(userId);
      res.status(200).json({ token });
      return;
    }

    if (req.method === "DELETE") {
      const token = bearerToken(req);
      if (token) await deleteSession(token);
      // Idempotent: signing out an already-dead session still succeeds.
      res.status(200).json({ ok: true });
      return;
    }

    res.status(405).json({ error: "method_not_allowed" });
  } catch (err) {
    console.error("account/session", (err as Error).message); // server-side only
    res.status(502).json({ error: "session_failed" });
  }
}
