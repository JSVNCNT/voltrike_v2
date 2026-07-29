import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';
import type { Plugin } from 'vite';
import react from '@vitejs/plugin-react';

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

export default defineConfig({
  plugins: [react(), firebaseMessagingWorker()],
  // The approved PSGC location source and shared logo live in the repository
  // assets folder. Vite publishes them without adding the nationwide data to
  // the initial JavaScript bundle.
  publicDir: '../assets',
});
