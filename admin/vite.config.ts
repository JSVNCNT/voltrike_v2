import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';
import type { Plugin } from 'vite';
import { loadEnv } from 'vite';
import react from '@vitejs/plugin-react';
import { sentryVitePlugin } from '@sentry/vite-plugin';

const messagingWorkerPath = fileURLToPath(
  new URL('./public/firebase-messaging-sw.js', import.meta.url),
);

function firebaseMessagingWorker(): Plugin {
  return {
    name: 'voltrike-firebase-messaging-worker',
    configureServer(server) {
      server.middlewares.use((request, response, next) => {
        if (request.url?.split('?')[0] !== '/firebase-messaging-sw.js') {
          next();
          return;
        }
        response.statusCode = 200;
        response.setHeader('Content-Type', 'text/javascript; charset=utf-8');
        response.setHeader('Service-Worker-Allowed', '/');
        response.end(readFileSync(messagingWorkerPath));
      });
    },
    generateBundle() {
      this.emitFile({
        type: 'asset',
        fileName: 'firebase-messaging-sw.js',
        source: readFileSync(messagingWorkerPath),
      });
    },
  };
}

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '');
  const authToken = process.env.SENTRY_AUTH_TOKEN || env.SENTRY_AUTH_TOKEN;
  const release = process.env.RENDER_GIT_COMMIT || process.env.GITHUB_SHA || env.VITE_SENTRY_RELEASE || '';
  const uploadSourceMaps = Boolean(authToken);

  return {
    plugins: [
      react(),
      firebaseMessagingWorker(),
      ...(uploadSourceMaps ? [sentryVitePlugin({
        authToken,
        org: process.env.SENTRY_ORG || env.SENTRY_ORG || 'voltrike',
        project: process.env.SENTRY_PROJECT || env.SENTRY_PROJECT || 'voltrike-admin',
        release: release ? { name: release } : undefined,
        sourcemaps: { filesToDeleteAfterUpload: ['./dist/**/*.map'] },
      })] : []),
    ],
    define: {
      'import.meta.env.VITE_SENTRY_RELEASE': JSON.stringify(release),
    },
    build: {
      sourcemap: uploadSourceMaps ? 'hidden' : false,
    },
    // The approved PSGC location source and shared logo live in the repository
    // assets folder. Vite publishes them without adding the nationwide data to
    // the initial JavaScript bundle.
    publicDir: '../assets',
  };
});
