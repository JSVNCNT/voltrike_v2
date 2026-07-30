import { createReadStream } from 'node:fs';
import { access } from 'node:fs/promises';
import { createServer } from 'node:http';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFile } from 'node:child_process';

const port = Number.parseInt(process.argv[2] ?? '8765', 10);
if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error('Port must be an integer between 1 and 65535.');
}

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const sourceDirectory = join(root, 'assets', 'regionJson');
const allowedFiles = new Set([
  'regions.json',
  'provinces.json',
  'cities-municipalities.json',
  'barangays.json',
]);

const adbPath = process.argv[3];
const deviceId = process.argv[4];
let reverseInFlight = false;
if (adbPath && deviceId) {
  const restoreReverse = () => {
    if (reverseInFlight) {
      return;
    }
    reverseInFlight = true;
    execFile(
      adbPath,
      ['-s', deviceId, 'reverse', `tcp:${port}`, `tcp:${port}`],
      () => {
        reverseInFlight = false;
      },
    );
  };
  restoreReverse();
  setInterval(restoreReverse, 250).unref();
}

const server = createServer(async (request, response) => {
  const fileName = decodeURIComponent(
    new URL(request.url ?? '/', 'http://localhost').pathname.slice(1),
  );
  if (request.method !== 'GET' || !allowedFiles.has(fileName)) {
    response.writeHead(404).end();
    return;
  }

  const filePath = join(sourceDirectory, fileName);
  try {
    await access(filePath);
    response.writeHead(200, {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
    });
    createReadStream(filePath).pipe(response);
  } catch {
    response.writeHead(500).end();
  }
});

server.listen(port, '127.0.0.1', () => {
  process.stdout.write(`PSGC benchmark server listening on ${port}\n`);
});
