'use strict';

const { onSchedule } = require('firebase-functions/v2/scheduler');
const { defineSecret, defineString } = require('firebase-functions/params');

const apiBaseUrl = defineString('VOLTRIKE_API_BASE_URL');
const internalKey = defineSecret('GO_LOCAL_INTERNAL_KEY');

const runGoMaintenance = onSchedule({
  region: 'asia-southeast1', schedule: 'every 1 minutes', secrets: [internalKey],
}, async () => {
  const baseUrl = apiBaseUrl.value().replace(/\/$/, '');
  if (!baseUrl || !internalKey.value()) throw new Error('Go maintenance endpoint is not configured.');
  const response = await fetch(`${baseUrl}/v1/maintenance/run`, {
    method: 'POST', headers: { 'X-Voltrike-Internal-Key': internalKey.value() },
  });
  if (!response.ok) throw new Error(`Go maintenance failed with HTTP ${response.status}.`);
});

module.exports = { runGoMaintenance };
