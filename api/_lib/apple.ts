// Sign in with Apple identity-token verification.
//
// The iOS app sends the short-lived Apple identity token (a JWT, obtained at
// sign-in) to /api/account/session exactly once. We verify it here against
// Apple's published public keys and derive the stable user identifier from the
// token's `sub` claim. Nothing downstream ever trusts a client-supplied userId —
// it always comes from a verified token (see _lib/session.ts).
//
// Required env: APPLE_BUNDLE_ID (the app's bundle id, == the token's `aud`).
// Defaults to com.otterpace.app.

import { createRemoteJWKSet, jwtVerify } from "jose";

const APPLE_ISSUER = "https://appleid.apple.com";

// Apple's rotating public keys. `createRemoteJWKSet` fetches + caches them and
// picks the right key by the token's `kid`, refreshing on rotation.
const APPLE_JWKS = createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"));

function bundleId(): string {
  return process.env.APPLE_BUNDLE_ID || "com.otterpace.app";
}

/**
 * Verify an Apple identity token and return the stable Apple user identifier
 * (`sub`). Throws if the signature, issuer, audience, or expiry is invalid — the
 * caller maps that to a 401. Never returns an unverified identity.
 */
export async function verifyAppleIdentityToken(idToken: string): Promise<string> {
  const { payload } = await jwtVerify(idToken, APPLE_JWKS, {
    issuer: APPLE_ISSUER,
    audience: bundleId(),
  });
  const sub = payload.sub;
  if (!sub || typeof sub !== "string") {
    throw new Error("apple_token_missing_sub");
  }
  return sub;
}
