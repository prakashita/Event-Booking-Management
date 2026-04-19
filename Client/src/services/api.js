/**
 * Shared API client for the Event Booking app.
 * Base URL includes /api/v1. On 401, dispatches 'auth:unauthorized' for the app to handle.
 */

const getBaseUrl = () => {
  const base = import.meta.env.VITE_API_BASE_URL || "http://localhost:8000";
  return `${base.replace(/\/$/, "")}/api/v1`;
};

const getToken = () => localStorage.getItem("auth_token");

const UNAUTHORIZED_EVENT = "auth:unauthorized";

function getHeaders(init = {}) {
  const token = getToken();
  const headers = new Headers(init.headers || {});
  if (token) {
    headers.set("Authorization", `Bearer ${token}`);
  }
  return headers;
}

async function request(method, path, body = undefined, options = {}) {
  const url = path.startsWith("http") ? path : `${getBaseUrl()}${path.startsWith("/") ? path : `/${path}`}`;
  const headers = getHeaders(options);
  const isJson = body != null && !(body instanceof FormData);
  if (isJson) {
    headers.set("Content-Type", "application/json");
  }
  const bodyPayload =
    body instanceof FormData ? body : isJson && typeof body !== "string" ? JSON.stringify(body) : body;
  const res = await fetch(url, {
    ...options,
    method,
    headers,
    // We use Bearer auth; avoid cross-site cookie/credentials issues.
    credentials: "omit",
    body: bodyPayload,
  });
  if (res.status === 401) {
    window.dispatchEvent(new CustomEvent(UNAUTHORIZED_EVENT));
  }
  return res;
}

async function parseJson(res) {
  const text = await res.text();
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

export const api = {
  getBaseUrl,
  getToken,
  UNAUTHORIZED_EVENT,

  async get(path, options = {}) {
    return request("GET", path, undefined, options);
  },

  async post(path, body, options = {}) {
    return request("POST", path, body, options);
  },

  async patch(path, body, options = {}) {
    return request("PATCH", path, body, options);
  },

  async put(path, body, options = {}) {
    return request("PUT", path, body, options);
  },

  async delete(path, options = {}) {
    return request("DELETE", path, undefined, options);
  },

  async getJson(path) {
    const res = await this.get(path);
    return parseJson(res);
  },

  async postJson(path, body) {
    const res = await this.post(path, body);
    return parseJson(res);
  },

  async patchJson(path, body) {
    const res = await this.patch(path, body);
    const data = await parseJson(res);
    if (!res.ok) {
      const d = data?.detail;
      let msg = "Request failed";
      if (typeof d === "string") msg = d;
      else if (Array.isArray(d)) {
        msg = d.map((e) => (typeof e?.msg === "string" ? e.msg : JSON.stringify(e))).join("; ");
      }
      throw new Error(msg);
    }
    return data;
  },
};

export default api;
