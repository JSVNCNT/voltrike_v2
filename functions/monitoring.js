'use strict';

const Sentry = require('@sentry/google-cloud-serverless');

const configuredRate = Number(process.env.SENTRY_TRACES_SAMPLE_RATE || '0.05');
const tracesSampleRate = Number.isFinite(configuredRate)
  ? Math.min(1, Math.max(0, configuredRate))
  : 0.05;
const ignoredFunctionCodes = new Set([
  'already-exists',
  'failed-precondition',
  'functions/already-exists',
  'functions/failed-precondition',
  'functions/invalid-argument',
  'functions/not-found',
  'functions/permission-denied',
  'functions/resource-exhausted',
  'functions/unauthenticated',
  'invalid-argument',
  'not-found',
  'permission-denied',
  'resource-exhausted',
  'unauthenticated',
]);

Sentry.init({
  dsn: String(process.env.SENTRY_DSN || '').trim(),
  enabled: Boolean(String(process.env.SENTRY_DSN || '').trim()),
  environment: process.env.SENTRY_ENVIRONMENT || 'development',
  release: process.env.SENTRY_RELEASE || undefined,
  sendDefaultPii: false,
  tracesSampleRate,
  beforeSend(event, hint) {
    const code = hint?.originalException?.code;
    if (typeof code === 'string' && ignoredFunctionCodes.has(code)) return null;
    event.user = undefined;
    event.extra = undefined;
    if (event.request) {
      event.request.data = undefined;
      event.request.cookies = undefined;
      event.request.query_string = undefined;
      const safeHeaders = {};
      for (const [key, value] of Object.entries(event.request.headers || {})) {
        if (['accept', 'content-type', 'user-agent'].includes(key.toLowerCase())) {
          safeHeaders[key] = value;
        }
      }
      event.request.headers = safeHeaders;
    }
    event.breadcrumbs = event.breadcrumbs?.map((breadcrumb) => ({
      ...breadcrumb,
      data: undefined,
    }));
    return event;
  },
});

module.exports = {
  wrapCallable: Sentry.wrapHttpFunction,
  wrapCloudEvent: Sentry.wrapCloudEventFunction,
};
