//
// Teslaris key host.
//
// Tesla's Fleet API requires each developer application's public key to
// be (and remain) hosted at a fixed path on a domain the app registers:
//   https://<domain>/.well-known/appspecific/com.tesla.3p.public-key.pem
//
// This Worker gives every Teslaris user such a domain in one request:
// the app generates the key pair locally (the private key never leaves
// the user's Mac), POSTs only the public key here, and gets back a
// dedicated subdomain that serves it.
//
//   POST https://teslaris-keys.weareheavy.dev/v1/keys   body: SPKI PEM
//     → 201 {"domain": "tesla-3f9c01d2ab.weareheavy.dev"}
//
//   GET  https://tesla-<id>.weareheavy.dev/.well-known/appspecific/com.tesla.3p.public-key.pem
//     → the stored PEM (this is what Tesla fetches)
//
// Abuse posture: uploads are validated down to the DER byte level (a
// 91-byte P-256 SPKI and nothing else), bodies over 1 KB are rejected,
// and KV's free-tier write cap (1k/day) is the flood ceiling — worst
// case new registrations fail for a day; nothing can generate a bill.
// Requests for hostnames this Worker doesn't own pass through to the
// origin untouched.
//

const PEM_PATH = "/.well-known/appspecific/com.tesla.3p.public-key.pem";
const KEY_HOST = /^tesla-[0-9a-f]{10}\.weareheavy\.dev$/;
const API_HOST = "teslaris-keys.weareheavy.dev";

// DER prefix of an SPKI for id-ecPublicKey on prime256v1, followed by a
// BIT STRING holding the 65-byte uncompressed point (0x04 …).
const SPKI_PREFIX = [
  0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02,
  0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03,
  0x42, 0x00, 0x04,
];

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const host = url.hostname.toLowerCase();

    if (host === API_HOST) {
      return handleApi(request, env);
    }

    if (KEY_HOST.test(host)) {
      if (request.method !== "GET" && request.method !== "HEAD") {
        return new Response("Method not allowed", { status: 405 });
      }
      if (url.pathname === PEM_PATH) {
        const pem = await env.KEYS.get(host);
        if (pem !== null) {
          return new Response(pem, {
            headers: {
              "content-type": "application/x-pem-file",
              // Tesla may fetch this at any time, forever. Cache hard;
              // keys are immutable once registered.
              "cache-control": "public, max-age=86400, immutable",
            },
          });
        }
      }
      return new Response("Not found", { status: 404 });
    }

    // Any other hostname (www, the apex via redirects, future sites):
    // not ours — hand the request to the origin untouched.
    return fetch(request);
  },
};

async function handleApi(request, env) {
  const url = new URL(request.url);

  // Tesla refuses to be an OAuth client for http://localhost redirects —
  // the portal accepts one, but sign-in then fails with "No policy
  // rules". Every working integration registers an HTTPS redirect, so
  // Tesla is sent here and we bounce straight back to the app's local
  // listener. Nothing is read, logged or stored: the query string is
  // passed through untouched.
  if (url.pathname === "/oauth/callback") {
    const target = `http://localhost:8973/callback${url.search}`;
    return new Response(
      `<!doctype html><meta charset="utf-8">` +
        `<meta http-equiv="refresh" content="0;url=${target.replace(/&/g, "&amp;")}">` +
        `<title>Teslaris</title>` +
        `<body style="font-family:-apple-system;padding:2em">` +
        `<h2>Signing you in…</h2>` +
        `<p>If nothing happens, <a href="${target.replace(/&/g, "&amp;")}">continue to Teslaris</a>.</p>`,
      {
        status: 200,
        headers: {
          "content-type": "text/html; charset=utf-8",
          // A one-time authorization code must never be cached.
          "cache-control": "no-store",
          refresh: `0;url=${target}`,
        },
      },
    );
  }

  if (url.pathname === "/v1/keys" && request.method === "POST") {
    return registerKey(request, env);
  }
  if (url.pathname === "/" && request.method === "GET") {
    return new Response(
      "Teslaris key host. POST an EC P-256 public key PEM to /v1/keys.\n" +
        "https://github.com/simonbusborg/teslaris\n",
      { headers: { "content-type": "text/plain" } },
    );
  }
  return new Response("Not found", { status: 404 });
}

async function registerKey(request, env) {
  const length = Number(request.headers.get("content-length") ?? "0");
  if (length > 1024) {
    return json(413, { error: "body too large" });
  }
  const body = (await request.text()).slice(0, 1024);

  const pem = normalizePEM(body);
  if (pem === null) {
    return json(400, { error: "expected an EC P-256 public key PEM (SPKI)" });
  }

  // Random, unguessable, and meaningless: 5 bytes → 10 hex chars.
  // Keys are write-once — an existing entry is never overwritten, so a
  // collision (≈2^-40) just draws another id rather than clobbering
  // somebody's registration.
  for (let attempt = 0; attempt < 5; attempt++) {
    const bytes = new Uint8Array(5);
    crypto.getRandomValues(bytes);
    const id = [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
    const domain = `tesla-${id}.weareheavy.dev`;

    if ((await env.KEYS.get(domain)) === null) {
      await env.KEYS.put(domain, pem);
      return json(201, { domain, path: PEM_PATH });
    }
  }
  return json(503, { error: "could not allocate a domain, please retry" });
}

// Returns the canonical PEM when the body is exactly one P-256 SPKI
// public key; null for everything else.
function normalizePEM(text) {
  const match = text.match(
    /^\s*-----BEGIN PUBLIC KEY-----\s*([A-Za-z0-9+/=\s]+?)\s*-----END PUBLIC KEY-----\s*$/,
  );
  if (!match) return null;
  const base64 = match[1].replace(/\s+/g, "");
  let der;
  try {
    der = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
  } catch {
    return null;
  }
  if (der.length !== 91) return null;
  for (let i = 0; i < SPKI_PREFIX.length; i++) {
    if (der[i] !== SPKI_PREFIX[i]) return null;
  }
  const lines = base64.match(/.{1,64}/g).join("\n");
  return `-----BEGIN PUBLIC KEY-----\n${lines}\n-----END PUBLIC KEY-----\n`;
}

function json(status, payload) {
  return new Response(JSON.stringify(payload) + "\n", {
    status,
    headers: { "content-type": "application/json" },
  });
}
