import { describe, it, expect, vi, beforeEach } from "vitest";

// /api/account/session mints/revokes bearer tokens. Mock the Apple verifier and
// the session store so we assert the handler's gating + status codes with no
// network and no real crypto/JWKS fetch.
const apple = vi.hoisted(() => ({ verifyAppleIdentityToken: vi.fn() }));
vi.mock("../../api/_lib/apple.ts", () => apple);

const sess = vi.hoisted(() => ({
  createSession: vi.fn(),
  deleteSession: vi.fn(),
  bearerToken: vi.fn(),
}));
vi.mock("../../api/_lib/session.ts", () => sess);

import handler from "../../api/account/session.ts";

function makeRes() {
  return {
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
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function run(req: any) {
  const res = makeRes();
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return Promise.resolve(handler(req as any, res as any)).then(() => res);
}

beforeEach(() => {
  vi.clearAllMocks();
  vi.spyOn(console, "error").mockImplementation(() => {});
});

describe("account/session", () => {
  it("POST verifies the Apple token and returns a minted bearer", async () => {
    apple.verifyAppleIdentityToken.mockResolvedValue("apple-sub-123");
    sess.createSession.mockResolvedValue("minted-token");
    const res = await run({ method: "POST", body: { identityToken: "a.b.c" } });
    expect(res.statusCode).toBe(200);
    expect(res.body).toEqual({ token: "minted-token" });
    expect(sess.createSession).toHaveBeenCalledWith("apple-sub-123");
  });

  it("POST 400s without an identity token", async () => {
    const res = await run({ method: "POST", body: {} });
    expect(res.statusCode).toBe(400);
    expect(apple.verifyAppleIdentityToken).not.toHaveBeenCalled();
  });

  it("POST 400s on an oversized identity token", async () => {
    const res = await run({ method: "POST", body: { identityToken: "x".repeat(9000) } });
    expect(res.statusCode).toBe(400);
    expect(apple.verifyAppleIdentityToken).not.toHaveBeenCalled();
  });

  it("POST 401s when the Apple token is invalid", async () => {
    apple.verifyAppleIdentityToken.mockRejectedValue(new Error("bad signature"));
    const res = await run({ method: "POST", body: { identityToken: "a.b.c" } });
    expect(res.statusCode).toBe(401);
    expect(sess.createSession).not.toHaveBeenCalled();
  });

  it("DELETE revokes the current session and is idempotent", async () => {
    sess.bearerToken.mockReturnValue("tok");
    sess.deleteSession.mockResolvedValue(undefined);
    const res = await run({ method: "DELETE", headers: { authorization: "Bearer tok" } });
    expect(res.statusCode).toBe(200);
    expect(sess.deleteSession).toHaveBeenCalledWith("tok");
  });

  it("DELETE without a token still succeeds (idempotent sign-out)", async () => {
    sess.bearerToken.mockReturnValue(null);
    const res = await run({ method: "DELETE", headers: {} });
    expect(res.statusCode).toBe(200);
    expect(sess.deleteSession).not.toHaveBeenCalled();
  });

  it("405s on an unsupported method", async () => {
    const res = await run({ method: "GET" });
    expect(res.statusCode).toBe(405);
  });
});
