'use strict';

const METADATA_IDENTITY_URL =
  'http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity';

class GoServiceError extends Error {
  constructor(code, message, status = 500) {
    super(message);
    this.name = 'GoServiceError';
    this.code = code;
    this.status = status;
  }
}

function normalizedMode(value) {
  return String(value || '').trim().toLowerCase() === 'on' ? 'on' : 'off';
}

function createGoServiceClient({
  baseUrl,
  quoteMode,
  dispatchMode,
  localInternalKey,
  timeoutMs = 9000,
  fetchImpl = globalThis.fetch,
  emulator = process.env.FUNCTIONS_EMULATOR === 'true',
} = {}) {
  let cachedIdentityToken = null;
  let identityTokenExpiresAt = 0;

  const resolve = (value) => typeof value === 'function' ? value() : value;
  const url = () => String(resolve(baseUrl) || '').trim().replace(/\/+$/, '');
  const quotesEnabled = () => normalizedMode(resolve(quoteMode)) === 'on' && url();
  const dispatchEnabled = () => normalizedMode(resolve(dispatchMode)) === 'on' && url();

  async function identityToken(audience) {
    if (emulator) return null;
    if (cachedIdentityToken && identityTokenExpiresAt > Date.now() + 30000) {
      return cachedIdentityToken;
    }
    const endpoint = new URL(METADATA_IDENTITY_URL);
    endpoint.searchParams.set('audience', audience);
    endpoint.searchParams.set('format', 'full');
    const response = await fetchImpl(endpoint, {
      headers: { 'Metadata-Flavor': 'Google' },
      signal: AbortSignal.timeout(Math.min(timeoutMs, 5000)),
    });
    if (!response.ok) {
      throw new GoServiceError(
        'unavailable',
        `Cloud Run identity token failed with ${response.status}.`,
        503,
      );
    }
    cachedIdentityToken = (await response.text()).trim();
    const payload = decodeJwtPayload(cachedIdentityToken);
    identityTokenExpiresAt = Number(payload?.exp || 0) * 1000;
    return cachedIdentityToken;
  }

  async function call(path, body) {
    const audience = url();
    if (!audience) {
      throw new GoServiceError('unavailable', 'Go service URL is not configured.', 503);
    }
    const headers = { 'Content-Type': 'application/json' };
    const token = await identityToken(audience);
    if (token) headers.Authorization = `Bearer ${token}`;
    const internalKey = String(resolve(localInternalKey) || '').trim();
    if (emulator && internalKey) {
      headers['X-Voltrike-Internal-Key'] = internalKey;
    }
    let response;
    try {
      response = await fetchImpl(`${audience}${path}`, {
        method: 'POST',
        headers,
        body: JSON.stringify(body || {}),
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch (error) {
      if (error instanceof GoServiceError) throw error;
      throw new GoServiceError(
        'unavailable',
        `Go service request failed: ${error?.message || 'network error'}`,
        503,
      );
    }
    const payload = await parseResponse(response);
    if (!response.ok) {
      throw new GoServiceError(
        payload?.error?.code || 'internal',
        payload?.error?.message || `Go service returned ${response.status}.`,
        response.status,
      );
    }
    return payload;
  }

  return {
    configured: () => Boolean(url()),
    quoteMode: () => normalizedMode(resolve(quoteMode)),
    dispatchMode: () => normalizedMode(resolve(dispatchMode)),
    quotesEnabled: () => Boolean(quotesEnabled()),
    dispatchEnabled: () => Boolean(dispatchEnabled()),
    computeQuote: (body) => call('/v1/quotes/compute', body),
    consumeQuote: (body) => call('/v1/quotes/consume', body),
    invalidatePolicy: () => call('/v1/policy/invalidate', {}),
    dispatchCandidates: (body) => call('/v1/dispatch/candidates', body),
  };
}

async function parseResponse(response) {
  const text = await response.text();
  if (!text) return {};
  try {
    return JSON.parse(text);
  } catch {
    throw new GoServiceError(
      'internal',
      'Go service returned an invalid JSON response.',
      response.status,
    );
  }
}

function decodeJwtPayload(token) {
  try {
    const encoded = String(token).split('.')[1];
    return JSON.parse(Buffer.from(encoded, 'base64url').toString('utf8'));
  } catch {
    return null;
  }
}

module.exports = {
  GoServiceError,
  createGoServiceClient,
  normalizedMode,
};
