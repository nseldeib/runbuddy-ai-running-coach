const fs = require("fs");
const path = require("path");
const { createIssue } = require("./scenario-issues");

// Hydration / interactivity probe for the headless capture browser.
//
// Background: a page can return HTTP 200, render visible content, log no
// console errors, and still be completely dead — the client framework never
// hydrated, so every button and handler is inert. The status / render /
// console / image gates all pass and the broken page sails through to the
// user (the catalog whose filter buttons did nothing). This probe asserts the
// page actually became interactive before the capture gate reports success,
// so a non-hydrating page can no longer pass `client-errors`.
//
// Stack assumption: WHICH framework's hydration we look for is data-driven
// from `.codeyam/stack.json` (or an explicit override) — never hardcoded into
// the capture flow. Stacks with no client runtime (backend services, CLIs,
// static HTML) are a documented no-op pass. Frameworks for which we have no
// reliable in-page attachment signal are ALSO a conservative pass: we never
// flag a page we cannot prove is dead, so a healthy Svelte / Solid / vanilla
// page is never a false negative. A new framework detector is a new entry in
// `detectors` below plus a `KNOWN_FRAMEWORKS` mapping — not an edit here.

// Frameworks we have an in-page attachment detector for. Inference only
// resolves to one of these; an unrecognised framework yields `null`, which
// the caller treats as "cannot determine" (conservative pass).
const KNOWN_FRAMEWORKS = ["react", "vue"];

// Read `.codeyam/stack.json` relative to the capture script's cwd (the project
// dir — `scenario_check.rs` sets `.current_dir(project_dir)`). Never throws: a
// missing or malformed file yields `null` so the probe degrades to a no-op
// rather than breaking a capture.
function readStackJson() {
  try {
    const raw = fs.readFileSync(path.join(".codeyam", "stack.json"), "utf8");
    return JSON.parse(raw);
  } catch (_) {
    return null;
  }
}

// Scan a stack descriptor's identity fields for a framework we can probe.
// Pure — no I/O — so the matching rules are unit-tested without a stack.json.
function inferFramework(stack) {
  if (!stack) return null;
  const haystack = [
    stack.id,
    stack.name,
    ...(Array.isArray(stack.technologies) ? stack.technologies : []),
  ]
    .filter((s) => typeof s === "string")
    .join(" ")
    .toLowerCase();
  for (const fw of KNOWN_FRAMEWORKS) {
    if (haystack.includes(fw)) return fw;
  }
  return null;
}

// Decide, from a stack descriptor, whether the capture should expect a
// hydrated client runtime and which framework to probe for. Pure.
//
// `capture.interactivity === false` is an explicit opt-out for stacks that
// render no client runtime. `capture.interactivity.framework` is an explicit
// override when inference can't see the framework in the identity fields.
// Otherwise we infer: a known client framework, or `routing.type ===
// "client-side"`, implies a runtime that must hydrate; backend / static / CLI
// stacks match neither and no-op.
function resolveInteractivityExpectation(stack) {
  const capture = (stack && stack.capture) || {};
  if (capture.interactivity === false) {
    return { expectInteractive: false, framework: null };
  }
  const explicit =
    capture.interactivity && typeof capture.interactivity === "object"
      ? capture.interactivity.framework
      : null;
  if (typeof explicit === "string" && explicit.length > 0) {
    return { expectInteractive: true, framework: explicit.toLowerCase() };
  }
  const framework = inferFramework(stack);
  const routingType =
    stack && stack.routing && typeof stack.routing.type === "string"
      ? stack.routing.type
      : null;
  const expectInteractive = framework != null || routingType === "client-side";
  return { expectInteractive, framework };
}

// Run the in-page detection inside the loaded frame. Read-only: it inspects
// DOM-node properties left by a framework's hydration but never clicks or
// mutates anything, so it is safe to run before the screenshot is taken.
//
// Returns `{ controlCount, frameworkAttached }` where `frameworkAttached` is
// `true` (runtime demonstrably attached), `false` (framework-owned controls
// exist but no attachment signal — the dead-hydration case), or `null` (no
// detector for this framework, OR every interactive control is delegated to a
// terminal/canvas widget with no hydration marker → cannot judge).
async function collectHydrationState(frame, { framework } = {}) {
  return frame.evaluate((fw) => {
    const SELECTOR =
      'button, [role="button"], a[href], input:not([type="hidden"]), select, textarea, summary, [onclick]';
    // Roots of third-party terminal/canvas widgets that mount imperatively and
    // wire their own (non-framework) event handlers — xterm's `.xterm`, any
    // `<canvas>`, or an element a component explicitly flags terminal-backed.
    // Interactive controls inside these (e.g. xterm's hidden helper
    // `<textarea>`) never carry framework attachment keys even on a fully
    // hydrated page, so judging hydration from them yields a false "not
    // interactive" verdict. Stack assumption: `.xterm` is xterm-specific; the
    // `<canvas>` and `[data-terminal-backed]` entries are framework-agnostic
    // escape hatches any widget-embedding component can use.
    const WIDGET_ROOT_SELECTOR = ".xterm, canvas, [data-terminal-backed]";

    const controls = Array.from(document.querySelectorAll(SELECTOR));
    const inWidget = (el) =>
      !!el &&
      typeof el.closest === "function" &&
      el.closest(WIDGET_ROOT_SELECTOR) != null;
    // Framework-owned controls: those NOT delegated to a terminal/canvas
    // widget. Only these can prove or disprove that the framework hydrated.
    const frameworkControls = controls.filter((el) => !inWidget(el));

    // Per-framework attachment detectors. Each returns true when the framework
    // has demonstrably attached its client runtime to a live node. The
    // presence of a detector for `fw` is itself the signal that we CAN judge
    // this framework; the default (no detector) means "cannot determine".
    const detectors = {
      react: (els) =>
        els.some(
          (el) =>
            !!el &&
            Object.keys(el).some(
              (k) =>
                k.startsWith("__reactFiber$") ||
                k.startsWith("__reactProps$") ||
                k.startsWith("__reactContainer$"),
            ),
        ),
      vue: (els) =>
        els.some(
          (el) =>
            !!el &&
            (el.__vue__ != null ||
              el.__vnode != null ||
              el.__vueParentComponent != null),
        ) || !!document.querySelector("[data-v-app]"),
    };

    const detector = detectors[fw];

    // Terminal/canvas scenarios prove hydration with an explicit, framework-
    // rendered `data-codeyam-hydrated` marker. It counts only when the
    // framework actually attached to it — a marker that exists in static HTML
    // but never hydrated fails the same detector and does not count.
    const markerEl = document.querySelector("[data-codeyam-hydrated]");
    const markerAttached = detector
      ? detector(markerEl ? [markerEl] : [])
      : false;

    let frameworkAttached;
    if (!detector) {
      // No detector for this framework — cannot judge (conservative pass).
      frameworkAttached = null;
    } else if (detector(frameworkControls) || markerAttached) {
      // A genuinely framework-owned control attached, or an explicit hydration
      // marker proves the framework ran — definitively hydrated.
      frameworkAttached = true;
    } else if (frameworkControls.length === 0) {
      // Controls exist but every one lives inside a terminal/canvas widget and
      // there is no marker — we cannot prove the page is dead, so never flag.
      frameworkAttached = null;
    } else {
      // Framework-owned controls rendered but none attached — the dead-island
      // signal the gate exists to catch.
      frameworkAttached = false;
    }

    return { controlCount: controls.length, frameworkAttached };
  }, framework || null);
}

// Turn a collected state into a `hydration` issue, or `null` to pass. Pure, so
// every branch is unit-tested without a browser.
//
// Pass when: no client runtime expected (no-op stacks); no interactive control
// to probe (a static content page in a client app is legitimately inert); the
// framework attached; OR we couldn't determine attachment (`null` — never
// false-positive). Flag only the proven-dead case: controls exist AND the
// framework's runtime is demonstrably not attached.
function interpretHydration({
  expectInteractive,
  controlCount,
  frameworkAttached,
  framework,
  url,
}) {
  if (!expectInteractive) return null;
  if (!(controlCount > 0)) return null;
  if (frameworkAttached !== false) return null;
  const fw = framework || "the client framework";
  const plural = controlCount === 1 ? "" : "s";
  return createIssue(
    "hydration",
    `Page rendered ${controlCount} interactive control${plural} but ${fw} never attached ` +
      `event handlers — the page is not interactive (hydration did not run). Client JS may ` +
      `not be executing; check the preview proxy and the browser console. Run ` +
      "`codeyam-editor editor diagnose-preview --path <route>` to pinpoint a proxy " +
      `HTML-injection blocker.`,
    { url: url ?? null },
  );
}

// Orchestrator called from the capture flow: resolve the expectation (from the
// project's stack.json unless the caller injects a `stack`), short-circuit when
// no client runtime is expected, collect the in-page state, and interpret it.
// Never throws — a probe failure must not break an otherwise-good capture.
async function probeInteractivity(frame, { url, stack } = {}) {
  const descriptor = stack !== undefined ? stack : readStackJson();
  const { expectInteractive, framework } =
    resolveInteractivityExpectation(descriptor);
  if (!expectInteractive) return null;
  let state;
  try {
    state = await collectHydrationState(frame, { framework });
  } catch (_) {
    return null;
  }
  return interpretHydration({
    expectInteractive: true,
    controlCount: state.controlCount,
    frameworkAttached: state.frameworkAttached,
    framework,
    url,
  });
}

module.exports = {
  KNOWN_FRAMEWORKS,
  readStackJson,
  inferFramework,
  resolveInteractivityExpectation,
  collectHydrationState,
  interpretHydration,
  probeInteractivity,
};
