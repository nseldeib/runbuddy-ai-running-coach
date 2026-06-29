#!/usr/bin/env node
// Report the processing + TestFlight review state of Otterpace builds in App Store Connect.
//
// Usage:
//   ASC_KEY_ID=... ASC_ISSUER_ID=... node Scripts/asc-build-status.mjs [bundleId] [version]
//
// Auth: signs an ES256 JWT with the ASC API key at
// ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8 (same key used for upload).
// Prints one line per matching build — its processingState (PROCESSING/VALID/…)
// and, when the build has been submitted for external TestFlight testing, its
// Beta App Review state (Waiting for Review / In Review / Approved / Rejected).
// Exit code reflects PROCESSING only: 0 when a build is VALID, 2 while still
// PROCESSING / not yet ingested, 1 on FAILED/INVALID or error. (Review state is
// informational and does not change the exit code — a VALID build can sit in the
// review queue for days, which is normal, not a failure.)

import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";

const KEY_ID = process.env.ASC_KEY_ID;
const ISSUER_ID = process.env.ASC_ISSUER_ID;
const BUNDLE_ID = process.argv[2] || "com.otterpace.app";
const VERSION = process.argv[3] || null; // build number string, e.g. "2"

if (!KEY_ID || !ISSUER_ID) {
  console.error("set ASC_KEY_ID and ASC_ISSUER_ID");
  process.exit(1);
}

const keyPath = `${os.homedir()}/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8`;
const privateKey = crypto.createPrivateKey(fs.readFileSync(keyPath));

function b64url(buf) {
  return Buffer.from(buf).toString("base64url");
}
function jwt() {
  const header = b64url(JSON.stringify({ alg: "ES256", kid: KEY_ID, typ: "JWT" }));
  const now = Math.floor(Date.now() / 1000);
  const payload = b64url(
    JSON.stringify({ iss: ISSUER_ID, iat: now, exp: now + 600, aud: "appstoreconnect-v1" }),
  );
  const signer = crypto.createSign("SHA256");
  signer.update(`${header}.${payload}`);
  const sig = signer.sign({ key: privateKey, dsaEncoding: "ieee-p1363" });
  return `${header}.${payload}.${b64url(sig)}`;
}

async function api(path) {
  const res = await fetch(`https://api.appstoreconnect.apple.com${path}`, {
    headers: { Authorization: `Bearer ${jwt()}` },
  });
  if (!res.ok) {
    throw new Error(`ASC API ${res.status} on ${path}: ${(await res.text()).slice(0, 300)}`);
  }
  return res.json();
}

const apps = await api(`/v1/apps?filter[bundleId]=${encodeURIComponent(BUNDLE_ID)}&fields[apps]=name`);
const app = apps.data?.[0];
if (!app) {
  console.error(`No app found for bundleId ${BUNDLE_ID} (is the App Store Connect app record created?)`);
  process.exit(1);
}

// NOTE: betaAppReviewSubmission must be in fields[builds] — a sparse fieldset
// filters relationships too, so omitting it drops the link and every build looks
// "not submitted" even when it's in the review queue.
let path = `/v1/builds?filter[app]=${app.id}&fields[builds]=version,processingState,uploadedDate,expired,betaAppReviewSubmission&include=betaAppReviewSubmission&fields[betaAppReviewSubmissions]=betaReviewState&limit=10&sort=-uploadedDate`;
if (VERSION) path += `&filter[version]=${encodeURIComponent(VERSION)}`;
const builds = await api(path);

if (!builds.data?.length) {
  console.log(`${app.attributes.name}: no builds ingested yet${VERSION ? ` for build ${VERSION}` : ""} (still processing upload).`);
  process.exit(2);
}

// Beta App Review submissions ride along in `included`, linked from each build's
// betaAppReviewSubmission relationship. Map them by id so we can annotate builds.
const reviewStateById = new Map();
for (const inc of builds.included ?? []) {
  if (inc.type === "betaAppReviewSubmissions") {
    reviewStateById.set(inc.id, inc.attributes?.betaReviewState ?? "UNKNOWN");
  }
}
// Apple's raw enum -> human label. A build with no submission was never sent for
// external review (internal testers don't need it), so there's nothing to wait on.
const REVIEW_LABEL = {
  WAITING_FOR_REVIEW: "Waiting for Review",
  IN_REVIEW: "In Review",
  APPROVED: "Approved",
  REJECTED: "Rejected",
};

let anyProcessing = false;
let anyValid = false;
for (const b of builds.data) {
  const a = b.attributes;
  const subId = b.relationships?.betaAppReviewSubmission?.data?.id;
  const rawReview = subId ? (reviewStateById.get(subId) ?? "UNKNOWN") : null;
  const review = rawReview
    ? `TestFlight review: ${REVIEW_LABEL[rawReview] ?? rawReview}`
    : "not submitted for external review";
  console.log(
    `build ${a.version}: ${a.processingState}` +
      (a.uploadedDate ? `  (uploaded ${a.uploadedDate})` : "") +
      (a.expired ? "  [expired]" : "") +
      `  | ${review}`,
  );
  if (a.processingState === "PROCESSING") anyProcessing = true;
  if (a.processingState === "VALID") anyValid = true;
}

if (anyProcessing) process.exit(2);
process.exit(anyValid ? 0 : 1);
