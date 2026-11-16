import { createServer } from 'vite';
import React from 'react';
import { renderToString } from 'react-dom/server';
import { readFile, writeFile } from 'node:fs/promises';

// Ship readable, indexable HTML while retaining React's interactive controls.
const server = await createServer({ server: { middlewareMode: true, hmr: false }, appType: 'custom' });
try {
  const { default: App } = await server.ssrLoadModule('/src/App.jsx');
  const productionHost = process.env.VERCEL_PROJECT_PRODUCTION_URL;
  const origin = productionHost ? new URL(`https://${productionHost}`).origin : null;
  for (const [file, pagePath] of [['index.html', '/'], ['privacy.html', '/privacy.html'], ['terms.html', '/terms.html']]) {
    let html = await readFile(`dist/${file}`, 'utf8');
    const markup = renderToString(React.createElement(App, { pagePath }));
    if (!html.includes('<div id="root"></div>')) throw new Error(`Missing render target in ${file}`);
    html = html.replace('<div id="root"></div>', () => `<div id="root">${markup}</div>`);
    if (origin) {
      const url = new URL(pagePath, origin).href;
      html = html.replace('</head>', `<link rel="canonical" href="${url}" /><meta property="og:url" content="${url}" /></head>`);
      html = html.replace('content="/images/ad-poster.jpg"', `content="${origin}/images/ad-poster.jpg"`);
    }
    await writeFile(`dist/${file}`, html);
    console.log(`Prerendered ${file}`);
  }
} finally { await server.close(); }
