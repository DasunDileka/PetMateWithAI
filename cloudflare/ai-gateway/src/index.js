/**
 * PetMate AI Gateway — Cloudflare Worker
 *
 * Purpose: keep the Gemini / OpenRouter API keys OFF the mobile client.
 * The Flutter app authenticates with Firebase, sends its Firebase ID token,
 * and this Worker verifies that token before spending any AI quota.
 *
 * Request:  POST /v1/ai
 *           Authorization: Bearer <firebase-id-token>
 *           { "task": "daily_insight" | "chat" | "trend" | "vet_summary",
 *             "system": "...", "messages": [{role, text}], "maxTokens": 800 }
 *
 * Response: { "ok": true, "provider": "gemini"|"openrouter", "model": "...",
 *             "text": "...", "latencyMs": 123 }
 *
 * Secrets (wrangler secret put): GEMINI_API_KEY, OPENROUTER_API_KEY
 * Vars (wrangler.toml):          FIREBASE_PROJECT_ID
 * Bindings (optional):           RATE_LIMIT (KV namespace)
 */

const GEMINI_MODEL = 'gemini-3.6-flash';
const OPENROUTER_MODEL = 'openai/gpt-oss-20b:free';

// Extra tokens reserved for Gemini 3's internal reasoning, on top of the
// visible answer length the caller requested.
const REASONING_ALLOWANCE_TOKENS = 1024;

// JWK form of Google's secure-token signing keys. Using the JWK endpoint (not
// the X.509 one) means WebCrypto can import the key directly, with no ASN.1
// parsing in the Worker.
const GOOGLE_JWK_URL =
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';

// Requests allowed per user per rolling window.
const RATE_LIMIT_MAX = 30;
const RATE_LIMIT_WINDOW_SECONDS = 60 * 10;

/* ------------------------------------------------------------------ utils */

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'access-control-allow-origin': '*',
      'access-control-allow-headers': 'authorization, content-type',
      'access-control-allow-methods': 'POST, OPTIONS',
    },
  });

const fail = (code, message, status) => json({ ok: false, code, message }, status);

function b64urlToBytes(input) {
  const pad = input.length % 4 === 0 ? '' : '='.repeat(4 - (input.length % 4));
  const b64 = (input + pad).replace(/-/g, '+').replace(/_/g, '/');
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

const decodeJson = (segment) =>
  JSON.parse(new TextDecoder().decode(b64urlToBytes(segment)));

/* --------------------------------------------------- Firebase ID token check */

let jwkCache = { expiresAt: 0, keys: null };

async function googleJwks() {
  const now = Date.now();
  if (jwkCache.keys && now < jwkCache.expiresAt) return jwkCache.keys;

  const res = await fetch(GOOGLE_JWK_URL);
  if (!res.ok) throw new Error('jwk_fetch_failed');

  // Respect Google's cache-control so we are not refetching on every request.
  const cc = res.headers.get('cache-control') || '';
  const maxAge = Number((cc.match(/max-age=(\d+)/) || [])[1] || 3600);

  const body = await res.json();
  const byKid = {};
  for (const key of body.keys || []) byKid[key.kid] = key;

  jwkCache = { keys: byKid, expiresAt: now + maxAge * 1000 };
  return byKid;
}

async function verifyFirebaseToken(token, projectId) {
  const parts = token.split('.');
  if (parts.length !== 3) throw new Error('malformed_token');

  const header = decodeJson(parts[0]);
  const payload = decodeJson(parts[1]);

  if (header.alg !== 'RS256') throw new Error('bad_alg');

  // Claim checks first — they are cheap and reject most bad tokens before we
  // pay for a signature verification.
  const now = Math.floor(Date.now() / 1000);
  if (payload.aud !== projectId) throw new Error('bad_audience');
  if (payload.iss !== `https://securetoken.google.com/${projectId}`) {
    throw new Error('bad_issuer');
  }
  if (!payload.sub) throw new Error('missing_subject');
  if (payload.exp <= now) throw new Error('token_expired');
  if (payload.iat > now + 300) throw new Error('token_issued_in_future');

  const jwks = await googleJwks();
  const jwk = jwks[header.kid];
  if (!jwk) throw new Error('unknown_kid');

  const key = await crypto.subtle.importKey(
    'jwk',
    { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: 'RS256', ext: true },
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['verify']
  );

  const verified = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    key,
    b64urlToBytes(parts[2]),
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`)
  );
  if (!verified) throw new Error('bad_signature');

  return payload;
}

/* ------------------------------------------------------------ rate limiting */

async function underRateLimit(env, uid) {
  if (!env.RATE_LIMIT) return true; // KV not bound (local dev) — fail open.
  const key = `rl:${uid}`;
  const current = Number((await env.RATE_LIMIT.get(key)) || 0);
  if (current >= RATE_LIMIT_MAX) return false;
  await env.RATE_LIMIT.put(key, String(current + 1), {
    expirationTtl: RATE_LIMIT_WINDOW_SECONDS,
  });
  return true;
}

/* ---------------------------------------------------------------- providers */

async function callGemini(env, system, messages, maxTokens) {
  const endpoint =
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;

  const res = await fetch(`${endpoint}?key=${env.GEMINI_API_KEY}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: system }] },
      contents: messages.map((m) => ({
        role: m.role === 'assistant' ? 'model' : 'user',
        parts: [{ text: m.text }],
      })),
      generationConfig: {
        temperature: 0.6,
        topP: 0.9,
        // Gemini 3 charges its internal reasoning against maxOutputTokens, so
        // the budget is the requested visible length plus an allowance.
        // Without this the answer truncates mid-sentence.
        maxOutputTokens: maxTokens + REASONING_ALLOWANCE_TOKENS,
        thinkingConfig: { thinkingLevel: 'low' },
      },
    }),
  });

  if (!res.ok) throw new Error(`gemini_http_${res.status}`);

  const data = await res.json();
  const text = (data?.candidates?.[0]?.content?.parts || [])
    .map((p) => p.text || '')
    .join('')
    .trim();

  if (!text) throw new Error('gemini_empty_response');
  return { text, model: GEMINI_MODEL };
}

async function callOpenRouter(env, system, messages, maxTokens) {
  const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: {
      authorization: `Bearer ${env.OPENROUTER_API_KEY}`,
      'content-type': 'application/json',
      'x-title': 'PetMate',
    },
    body: JSON.stringify({
      model: OPENROUTER_MODEL,
      max_tokens: maxTokens,
      temperature: 0.6,
      messages: [
        { role: 'system', content: system },
        ...messages.map((m) => ({
          role: m.role === 'assistant' ? 'assistant' : 'user',
          content: m.text,
        })),
      ],
    }),
  });

  if (!res.ok) throw new Error(`openrouter_http_${res.status}`);

  const data = await res.json();
  const text = data?.choices?.[0]?.message?.content?.trim();
  if (!text) throw new Error('openrouter_empty_response');
  return { text, model: OPENROUTER_MODEL };
}

/* -------------------------------------------------------------------- entry */

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return json({ ok: true });
    if (request.method !== 'POST') return fail('method_not_allowed', 'Use POST.', 405);

    const url = new URL(request.url);
    if (url.pathname !== '/v1/ai') return fail('not_found', 'Unknown endpoint.', 404);

    const auth = request.headers.get('authorization') || '';
    if (!auth.startsWith('Bearer ')) {
      return fail('unauthenticated', 'Missing bearer token.', 401);
    }

    let claims;
    try {
      claims = await verifyFirebaseToken(auth.slice(7), env.FIREBASE_PROJECT_ID);
    } catch {
      // Never echo the token or the internal reason verbatim to the client.
      return fail('unauthenticated', 'Invalid or expired session.', 401);
    }

    if (!(await underRateLimit(env, claims.sub))) {
      return fail('rate_limited', 'Too many AI requests. Try again shortly.', 429);
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return fail('bad_request', 'Body must be JSON.', 400);
    }

    const system = typeof body.system === 'string' ? body.system.slice(0, 6000) : '';
    const messages = Array.isArray(body.messages) ? body.messages.slice(-12) : [];
    const maxTokens = Math.min(Math.max(Number(body.maxTokens) || 700, 64), 2048);

    if (!messages.length) return fail('bad_request', 'messages[] is required.', 400);

    const started = Date.now();

    // Gemini is primary; the OpenRouter free tier is the resilience fallback.
    try {
      const r = await callGemini(env, system, messages, maxTokens);
      return json({
        ok: true,
        provider: 'gemini',
        model: r.model,
        text: r.text,
        latencyMs: Date.now() - started,
      });
    } catch {
      try {
        const r = await callOpenRouter(env, system, messages, maxTokens);
        return json({
          ok: true,
          provider: 'openrouter',
          model: r.model,
          text: r.text,
          latencyMs: Date.now() - started,
          note: 'primary_provider_unavailable',
        });
      } catch {
        return fail(
          'ai_unavailable',
          'The AI service is temporarily unavailable. Please try again.',
          503
        );
      }
    }
  },
};
