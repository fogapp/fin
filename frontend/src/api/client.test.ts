import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { api, getToken, setToken, clearToken } from "./client";

describe("token storage helpers", () => {
  beforeEach(() => localStorage.clear());

  it("round-trips a token through localStorage", () => {
    expect(getToken()).toBeNull();
    setToken("abc-123");
    expect(getToken()).toBe("abc-123");
    expect(localStorage.getItem("fin_api_token")).toBe("abc-123");
  });

  it("moves a token stored under the pre-rename key", () => {
    localStorage.setItem("manor_api_token", "legacy-1");
    expect(getToken()).toBe("legacy-1");
    expect(localStorage.getItem("fin_api_token")).toBe("legacy-1");
    expect(localStorage.getItem("manor_api_token")).toBeNull();
  });

  it("prefers the current key over a leftover legacy one", () => {
    localStorage.setItem("manor_api_token", "legacy-1");
    setToken("current-2");
    expect(getToken()).toBe("current-2");
  });

  it("clearToken removes the stored value", () => {
    setToken("abc-123");
    clearToken();
    expect(getToken()).toBeNull();
  });
});

describe("api request wrapper", () => {
  let fetchMock: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    localStorage.clear();
    fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
  });

  afterEach(() => vi.unstubAllGlobals());

  function jsonResponse(body: unknown, { status = 200 }: { status?: number } = {}) {
    return Promise.resolve({
      ok: status >= 200 && status < 300,
      status,
      json: () => Promise.resolve(body),
    } as Response);
  }

  it("prefixes every path with /api/v1", async () => {
    fetchMock.mockReturnValueOnce(jsonResponse({ ok: true }));
    await api.get("/dashboard");
    expect(fetchMock).toHaveBeenCalledWith("/api/v1/dashboard", expect.any(Object));
  });

  it("attaches an Authorization header when a token is set", async () => {
    setToken("my-token");
    fetchMock.mockReturnValueOnce(jsonResponse({}));
    await api.get("/me");
    const [, opts] = fetchMock.mock.calls[0];
    expect(opts.headers).toMatchObject({
      "Content-Type": "application/json",
      Authorization: "Bearer my-token",
    });
  });

  it("omits Authorization when no token is set", async () => {
    fetchMock.mockReturnValueOnce(jsonResponse({}));
    await api.get("/me");
    const [, opts] = fetchMock.mock.calls[0];
    expect(opts.headers.Authorization).toBeUndefined();
  });

  it("JSON-stringifies the POST body", async () => {
    fetchMock.mockReturnValueOnce(jsonResponse({ id: "1" }));
    await api.post("/tags", { name: "lunch" });
    const [, opts] = fetchMock.mock.calls[0];
    expect(opts.method).toBe("POST");
    expect(opts.body).toBe(JSON.stringify({ name: "lunch" }));
  });

  it("PATCH and DELETE set the right method", async () => {
    fetchMock.mockReturnValueOnce(jsonResponse({}));
    await api.patch("/tags/1", { name: "x" });
    expect(fetchMock.mock.calls[0][1].method).toBe("PATCH");

    fetchMock.mockReturnValueOnce(jsonResponse({}, { status: 204 }));
    await api.delete("/tags/1");
    expect(fetchMock.mock.calls[1][1].method).toBe("DELETE");
  });

  it("returns the parsed JSON body on success", async () => {
    fetchMock.mockReturnValueOnce(jsonResponse({ name: "Coffee", id: "abc" }));
    const result = await api.get<{ name: string; id: string }>("/tags/abc");
    expect(result).toEqual({ name: "Coffee", id: "abc" });
  });

  it("returns undefined for 204 No Content without parsing", async () => {
    const noJson = vi.fn();
    fetchMock.mockReturnValueOnce(
      Promise.resolve({ ok: true, status: 204, json: noJson } as unknown as Response),
    );
    const result = await api.delete<void>("/tags/abc");
    expect(result).toBeUndefined();
    expect(noJson).not.toHaveBeenCalled();
  });

  it("throws 'unauthorized' on 401 regardless of body", async () => {
    fetchMock.mockReturnValueOnce(jsonResponse({ error: "Missing token" }, { status: 401 }));
    await expect(api.get("/me")).rejects.toThrow("unauthorized");
  });

  it("throws with body.error message on a non-OK response", async () => {
    fetchMock.mockReturnValueOnce(
      jsonResponse({ error: "Bad merchant name" }, { status: 422 }),
    );
    await expect(api.post("/merchants", { name: "" })).rejects.toThrow("Bad merchant name");
  });

  it("joins body.errors[] when no top-level error string is present", async () => {
    fetchMock.mockReturnValueOnce(
      jsonResponse({ errors: [ "Name can't be blank", "Position is invalid" ] }, { status: 422 }),
    );
    await expect(api.post("/x", {})).rejects.toThrow(
      "Name can't be blank, Position is invalid",
    );
  });

  it("falls back to 'HTTP <status>' when the error body has nothing useful", async () => {
    fetchMock.mockReturnValueOnce(jsonResponse({}, { status: 500 }));
    await expect(api.get("/dashboard")).rejects.toThrow("HTTP 500");
  });

  it("handles a non-JSON error body without crashing", async () => {
    fetchMock.mockReturnValueOnce(
      Promise.resolve({
        ok: false,
        status: 502,
        json: () => Promise.reject(new Error("bad json")),
      } as unknown as Response),
    );
    await expect(api.get("/x")).rejects.toThrow("HTTP 502");
  });
});
