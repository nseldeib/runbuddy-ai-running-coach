import { describe, it, expect, vi, beforeEach } from "vitest";

// The coach handler constructs `new Anthropic({apiKey}).messages.create(...)`.
// Mock the SDK so no real Claude call is made and we control every reply/error.
const createMock = vi.fn();
vi.mock("@anthropic-ai/sdk", () => ({
  default: class {
    messages = { create: createMock };
    constructor(_opts: unknown) {}
  },
}));

import handler from "../../api/coach.ts";

interface MockRes {
  statusCode: number;
  body: unknown;
  status: (c: number) => MockRes;
  json: (b: unknown) => MockRes;
}

function makeRes(): MockRes {
  const res = {
    statusCode: 0,
    body: undefined as unknown,
    status(c: number) {
      this.statusCode = c;
      return this;
    },
    json(b: unknown) {
      this.body = b;
      return this;
    },
  };
  return res;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function call(req: any) {
  const res = makeRes();
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return { res, done: handler(req as any, res as any) };
}

function textReply(json: string) {
  return { stop_reason: "end_turn", content: [{ type: "text", text: json }] };
}

beforeEach(() => {
  createMock.mockReset();
});

describe("coach handler", () => {
  // Only POST is allowed.
  it("rejects non-POST with 405", async () => {
    const { res, done } = call({ method: "GET", headers: {}, body: {} });
    await done;
    expect(res.statusCode).toBe(405);
  });

  // A missing or too-short Anthropic key is a 400 (not a 401 — nothing was sent).
  it("requires an api key", async () => {
    const { res, done } = call({ method: "POST", headers: {}, body: { question: "hi" } });
    await done;
    expect(res.statusCode).toBe(400);
    expect((res.body as { error: string }).error).toBe("missing_key");
  });

  // An empty question is rejected before any model call.
  it("requires a question", async () => {
    const { res, done } = call({ method: "POST", headers: { "x-anthropic-key": "sk-ant-xyz" }, body: { question: "   " } });
    await done;
    expect(res.statusCode).toBe(400);
    expect((res.body as { error: string }).error).toBe("missing_question");
    expect(createMock).not.toHaveBeenCalled();
  });

  // A valid structured reply is decoded and returned as the app's CoachReply.
  it("returns a parsed reply on success", async () => {
    createMock.mockResolvedValue(textReply(JSON.stringify({ text: "Easy walk today.", mood: "recovery", safetyFlag: true })));
    const { res, done } = call({ method: "POST", headers: { "x-anthropic-key": "sk-ant-xyz" }, body: { question: "run or rest?" } });
    await done;
    expect(res.statusCode).toBe(200);
    expect(res.body).toMatchObject({ text: "Easy walk today.", mood: "recovery", safetyFlag: true });
  });

  // A safety refusal degrades to a friendly on-topic redirect (still 200).
  it("handles a refusal stop_reason gracefully", async () => {
    createMock.mockResolvedValue({ stop_reason: "refusal", content: [] });
    const { res, done } = call({ method: "POST", headers: { "x-anthropic-key": "sk-ant-xyz" }, body: { question: "..." } });
    await done;
    expect(res.statusCode).toBe(200);
    expect((res.body as { mood: string }).mood).toBe("ready");
  });

  // A response with no text block is an upstream 502.
  it("502s when there is no text block", async () => {
    createMock.mockResolvedValue({ stop_reason: "end_turn", content: [] });
    const { res, done } = call({ method: "POST", headers: { "x-anthropic-key": "sk-ant-xyz" }, body: { question: "hi" } });
    await done;
    expect(res.statusCode).toBe(502);
  });

  // Malformed JSON in the text block degrades gracefully to a 200, not a 500 —
  // the user's key worked and was billed.
  it("degrades on malformed JSON", async () => {
    createMock.mockResolvedValue(textReply("not json at all"));
    const { res, done } = call({ method: "POST", headers: { "x-anthropic-key": "sk-ant-xyz" }, body: { question: "hi" } });
    await done;
    expect(res.statusCode).toBe(200);
    expect((res.body as { mood: string }).mood).toBe("ready");
  });

  // A 401 from Anthropic maps to invalid_key.
  it("maps a 401 to invalid_key", async () => {
    createMock.mockRejectedValue(Object.assign(new Error("unauthorized"), { status: 401 }));
    const { res, done } = call({ method: "POST", headers: { "x-anthropic-key": "sk-ant-xyz" }, body: { question: "hi" } });
    await done;
    expect(res.statusCode).toBe(401);
    expect((res.body as { error: string }).error).toBe("invalid_key");
  });

  // A 429 maps to rate_limited.
  it("maps a 429 to rate_limited", async () => {
    createMock.mockRejectedValue(Object.assign(new Error("slow down"), { status: 429 }));
    const { res, done } = call({ method: "POST", headers: { "x-anthropic-key": "sk-ant-xyz" }, body: { question: "hi" } });
    await done;
    expect(res.statusCode).toBe(429);
  });

  // Any other upstream error is a generic 502 (no internal detail leaked).
  it("maps other errors to a generic 502", async () => {
    createMock.mockRejectedValue(Object.assign(new Error("boom"), { status: 500 }));
    const { res, done } = call({ method: "POST", headers: { "x-anthropic-key": "sk-ant-xyz" }, body: { question: "hi" } });
    await done;
    expect(res.statusCode).toBe(502);
    expect((res.body as { error: string }).error).toBe("upstream_error");
  });

  // BE-8: the user's API key must never reach the logs, even on the error path.
  it("never logs the Anthropic API key", async () => {
    const errSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    const SECRET = "sk-ant-super-secret-key";
    createMock.mockRejectedValue(Object.assign(new Error("boom"), { status: 500 }));
    const { done } = call({ method: "POST", headers: { "x-anthropic-key": SECRET }, body: { question: "hi" } });
    await done;
    const logged = [...errSpy.mock.calls, ...logSpy.mock.calls].flat().join(" ");
    expect(logged).not.toContain(SECRET);
    errSpy.mockRestore();
    logSpy.mockRestore();
  });

  // Over-long inputs are rejected before any model call (BE-4 size bounds).
  it("413s on an over-long question", async () => {
    const { res, done } = call({
      method: "POST",
      headers: { "x-anthropic-key": "sk-ant-xyz" },
      body: { question: "x".repeat(3000) },
    });
    await done;
    expect(res.statusCode).toBe(413);
    expect(createMock).not.toHaveBeenCalled();
  });
});
