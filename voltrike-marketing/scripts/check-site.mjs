import assert from 'node:assert/strict';
import { readFile, readdir, stat } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { createHash } from 'node:crypto';

const root = resolve('dist');
const baseline = JSON.parse(await readFile(new URL('./media-baseline.json', import.meta.url), 'utf8'));
const hash = data => createHash('sha256').update(data).digest('hex');
const base = process.argv[2];
const pages = ['index.html', 'privacy.html', 'terms.html'];
const expectedSections = ['our-film', 'how-it-works', 'experience', 'safety', 'purpose', 'demo', 'download', 'faq'];
const apk = 'https://github.com/JSVNCNT/voltrike_v2/releases/latest/download/voltrike.apk';
const home = await readFile(join(root, 'index.html'), 'utf8');
assert.match(home, /A better way/);
assert.equal((home.match(/<h1\b/g) || []).length, 1);
for (const id of expectedSections) assert.ok(home.includes(`id="${id}"`), `Missing section: ${id}`);
assert.ok(home.includes(apk), 'APK destination missing');
assert.ok(!home.includes('<video'), 'Videos should wait for a play click');
assert.ok(!home.includes('youtube.com') && !home.includes('youtube-nocookie.com'));
assert.match(await readFile(join(root, 'privacy.html'), 'utf8'), /hosting provider may process/);
assert.match(await readFile(join(root, 'terms.html'), 'utf8'), /does not dispatch emergency services/);

const resources = new Set(['/favicon.svg', '/images/app-qr.svg',
  ...['fare-review', 'trip-progress', 'driver-offer', 'driver-cash', 'admin-toda'].map(n => `/screens/${n}.webp`)]);
for (const page of pages) {
  const html = await readFile(join(root, page), 'utf8');
  for (const m of html.matchAll(/(?:src|href|content)="(\/[^"#?]*)"/g)) {
    if (m[1] !== '/') resources.add(m[1]);
  }
  for (const m of html.matchAll(/href="#([^"]+)"/g)) assert.ok(html.includes(`id="${m[1]}"`), `Broken anchor in ${page}: ${m[1]}`);
}
for (const resource of resources) assert.ok((await stat(join(root, resource))).isFile(), `Missing asset: ${resource}`);
assert.equal(hash(await readFile(join(root, 'images/app-qr.svg'))), baseline.appQrSha256, 'Existing QR must be preserved');

function boxes(buffer, start = 0, end = buffer.length) {
  const result=[];
  for (let p = start; p + 8 <= end;) {
    let size=buffer.readUInt32BE(p), header=8;
    if (size===1) { size=Number(buffer.readBigUInt64BE(p+8)); header=16; }
    if (size===0) size=end-p;
    assert.ok(size>=header && p+size<=end, 'Invalid MP4 box');
    result.push({ type: buffer.toString('ascii',p+4,p+8), start:p+header, end:p+size });
    p+=size;
  }
  return result;
}
function inspectVideo(buffer) {
  const top=boxes(buffer), moov=top.find(b=>b.type==='moov'), mdat=top.find(b=>b.type==='mdat');
  assert.ok(moov && mdat && moov.start<mdat.start, 'Video needs fast-start metadata');
  const movie=boxes(buffer,moov.start,moov.end), mvhd=movie.find(b=>b.type==='mvhd');
  const version=buffer[mvhd.start];
  const scale=buffer.readUInt32BE(mvhd.start+(version ? 20 : 12));
  const duration=(version ? Number(buffer.readBigUInt64BE(mvhd.start+24)) : buffer.readUInt32BE(mvhd.start+16))/scale;
  const handlers=movie.filter(b=>b.type==='trak').map(trak=>{
    const mdia=boxes(buffer,trak.start,trak.end).find(b=>b.type==='mdia');
    const hdlr=boxes(buffer,mdia.start,mdia.end).find(b=>b.type==='hdlr');
    return buffer.toString('ascii',hdlr.start+8,hdlr.start+12);
  });
  return { duration, audio: handlers.filter(h=>h==='soun').length, video: handlers.filter(h=>h==='vide').length };
}
for (const name of ['voltrike-ad', 'voltrike-demo']) {
  const data=await readFile(join(root, `videos/${name}.mp4`));
  const info=inspectVideo(data);
  assert.equal(info.video,1);
  assert.ok(info.duration>0 && info.duration<180);
  if (name==='voltrike-demo') {
    assert.equal(info.audio,0,'Demo must remain silent');
    assert.equal(hash(data), baseline.approvedDemoSha256, 'Demo must retain the approved edit and censorship');
  }
  console.log(`${name}: ${info.duration.toFixed(2)}s, ${info.audio} audio track(s), fast-start MP4`);
  if (base) {
    const response=await fetch(new URL(`/videos/${name}.mp4`,base),{headers:{Range:'bytes=0-1023'}});
    assert.equal(response.status,206,'Video seeking needs range responses');
    assert.match(response.headers.get('content-type'),/video\/mp4/);
    assert.match(response.headers.get('content-range'),/^bytes 0-1023\//);
    assert.equal((await response.arrayBuffer()).byteLength,1024);
  }
}
if (base) {
  await Promise.all([...resources,...pages.map(p=>`/${p}`)].map(async path=>{
    const response=await fetch(new URL(path,base),{method:'HEAD'});
    assert.equal(response.status,200,`HTTP failure: ${path}`);
  }));
  console.log('HTTP pages/assets and seekable MP4 delivery passed.');
}
async function totalSize(directory) {
  let sum=0;
  for (const entry of await readdir(directory,{withFileTypes:true})) {
    const path=join(directory,entry.name);
    sum+=entry.isDirectory() ? await totalSize(path) : (await stat(path)).size;
  }
  return sum;
}
const size=await totalSize(root);
assert.ok(size<100_000_000,'Keep the standalone site below the Hobby CLI upload allowance');
console.log(`All checks passed. Built site: ${(size/1e6).toFixed(1)} MB. ${resources.size} linked assets checked.`);
