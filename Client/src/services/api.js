/**
 * Shared API client for the Event Booking app.
 * Base URL includes /api/v1.
 * - On 401: dispatches 'auth:unauthorized' for session-expired handling.
 * - On 5xx: dispatches 'api:server_error' for global error banner.
 * - On fetch failure (network error): dispatches 'api:network_error'.
 */

export const API_EVENTS = {
  UNAUTHORIZED: "auth:unauthorized",
  SERVER_ERROR: "api:server_error",
  NETWORK_ERROR: "api:network_error",
};

const getBaseUrl = () => {
  const base = import.meta.env.VITE_API_BASE_URL || "http://localhost:8000";
  return `${base.replace(/\/$/, "")}/api/v1`;
};

const getToken = () => localStorage.getItem("auth_token");

const UNAUTHORIZED_EVENT = API_EVENTS.UNAUTHORIZED;

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
  let res;
  try {
    res = await fetch(url, {
      ...options,
      method,
      headers,
      credentials: "include",
      body: bodyPayload,
    });
  } catch (err) {
    window.dispatchEvent(
      new CustomEvent(API_EVENTS.NETWORK_ERROR, { detail: { message: err?.message || "Network error" } })
    );
    throw err;
  }
  if (res.status === 401) {
    window.dispatchEvent(new CustomEvent(UNAUTHORIZED_EVENT));
  } else if (res.status >= 500) {
    window.dispatchEvent(
      new CustomEvent(API_EVENTS.SERVER_ERROR, {
        detail: { status: res.status, message: `Server error (${res.status})` },
      })
    );
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
  API_EVENTS,

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
};

export default api;
