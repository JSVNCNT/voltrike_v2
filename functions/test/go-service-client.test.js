'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {
  GoServiceError,
  createGoServiceClient,
  normalizedMode,
} = require('../go-service-client');

test('mode is fail-closed unless explicitly on', () => {
  assert.equal(normalizedMode('on'), 'on');
  assert.equal(normalizedMode(' ON '), 'on');
  assert.equal(normalizedMode('shadow'), 'off');
  assert.equal(normalizedMode(undefined), 'off');
});

test('emulator client sends the local key and quote body', async () => {
  const calls = [];
  const client = createGoServiceClient({
    baseUrl: 'http://127.0.0.1:8080/',
    quoteMode: 'on',
    dispatchMode: 'off',
    localInternalKey: 'local-secret',
    emulator: true,
    fetchImpl: async (url, options) => {
      calls.push({ url, options });
      return new Response(JSON.stringify({ quote: { distanceMeters: 123 } }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      });
    },
  });
  const result = await client.computeQuote({ actorId: 'passenger' });
  assert.equal(result.quote.distanceMeters, 123);
  assert.equal(client.configured(), true);
  assert.equal(calls[0].url, 'http://127.0.0.1:8080/v1/quotes/compute');
  assert.equal(calls[0].options.headers['X-Voltrike-Internal-Key'], 'local-secret');
  assert.equal(JSON.parse(calls[0].options.body).actorId, 'passenger');
});

test('structured Go errors remain machine readable', async () => {
  const client = createGoServiceClient({
    baseUrl: 'http://127.0.0.1:8080',
    quoteMode: 'on',
    emulator: true,
    fetchImpl: async () => new Response(JSON.stringify({
      error: { code: 'failed_precondition', message: 'Quote expired.' },
    }), { status: 412 }),
  });
  await assert.rejects(
    client.computeQuote({}),
    (error) => error instanceof GoServiceError &&
      error.code === 'failed_precondition' && error.status === 412,
  );
});
