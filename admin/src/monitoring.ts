import * as Sentry from '@sentry/react';

const dsn = import.meta.env.VITE_SENTRY_DSN?.trim() ?? '';
const configuredRate = Number(import.meta.env.VITE_SENTRY_TRACES_SAMPLE_RATE ?? '0.05');
const tracesSampleRate = Number.isFinite(configuredRate)
  ? Math.min(1, Math.max(0, configuredRate))
  : 0.05;

Sentry.init({
  dsn,
  enabled: dsn.length > 0,
  environment: import.meta.env.VITE_SENTRY_ENVIRONMENT || 'development',
  release: import.meta.env.VITE_SENTRY_RELEASE || undefined,
  sendDefaultPii: false,
  enableLogs: false,
  tracesSampleRate,
  replaysSessionSampleRate: 0,
  replaysOnErrorSampleRate: 0,
  beforeSend(event) {
    // VolTrike events should contain diagnostic stack information, not account,
    // location, message, authentication, or request payload data.
    event.user = undefined;
    event.extra = undefined;
    if (event.request) {
      event.request.data = undefined;
      event.request.cookies = undefined;
      event.request.query_string = undefined;
      if (event.request.headers) {
        const safeHeaders: Record<string, string> = {};
        for (const [key, value] of Object.entries(event.request.headers)) {
          if (['accept', 'content-type', 'user-agent'].includes(key.toLowerCase())) {
            safeHeaders[key] = value;
          }
        }
        event.request.headers = safeHeaders;
      }
    }
    event.breadcrumbs = event.breadcrumbs?.map((breadcrumb) => ({
      ...breadcrumb,
      data: undefined,
    }));
    return event;
  },
});

export { Sentry };
