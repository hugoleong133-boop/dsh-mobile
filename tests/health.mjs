#!/usr/bin/env node
/**
 * dsh-mobile 健康检查：用 PIN 配对一次，然后把 index 声明的每个模块 URL 都取回来。
 *
 *   node tests/health.mjs --url http://192.168.1.124:8765 --pin 338599
 *
 * 判定标准：index 200 且长度合理、所有 resources 200 且非空、无超时。
 * 这个检查覆盖的正是手机 Safari 启动时会走的全部 HTTP 路径；
 * WebSocket 另由 --ws 单独探（默认开）。
 */

import http from 'node:http';
import { randomBytes } from 'node:crypto';

const args = process.argv.slice(2);
const opt = { url: 'http://127.0.0.1:8765', pin: '', ws: true, timeout: 20000 };
for (let i = 0; i < args.length; i += 1) {
  if (args[i] === '--url') opt.url = args[++i];
  else if (args[i] === '--pin') opt.pin = args[++i];
  else if (args[i] === '--no-ws') opt.ws = false;
  else if (args[i] === '--timeout') opt.timeout = Number(args[++i]);
  else throw new Error(`unknown argument ${args[i]}`);
}

const base = new URL(opt.url);
const host = base.hostname;
const port = Number(base.port || 80);

function request(path, { method = 'GET', headers = {}, accept = '*/*' } = {}) {
  return new Promise((resolve) => {
    const req = http.request(
      { host, port, path, method, headers: { Accept: accept, ...headers } },
      (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => {
          const body = Buffer.concat(chunks);
          resolve({ status: res.statusCode || 0, headers: res.headers, body });
        });
      },
    );
    req.on('error', (e) => resolve({ status: 0, headers: {}, body: Buffer.alloc(0), error: e.message }));
    req.setTimeout(opt.timeout, () => {
      req.destroy();
      resolve({ status: 0, headers: {}, body: Buffer.alloc(0), error: 'timeout' });
    });
    req.end();
  });
}

function cookieFrom(res) {
  const raw = res.headers['set-cookie'];
  if (!raw) return undefined;
  return raw.map((c) => c.split(';')[0]).join('; ');
}

async function pair() {
  if (!opt.pin) return undefined;
  const res = await request(`/?k=${encodeURIComponent(opt.pin)}`, { accept: 'text/html' });
  const cookie = cookieFrom(res);
  if (!cookie) {
    console.log(`pair: status ${res.status}, no cookie — PIN 不对或服务没起`);
    process.exit(2);
  }
  console.log(`pair: ok (${cookie.split('=')[0]} set)`);
  return cookie;
}

async function checkWs(cookie) {
  const key = randomBytes(16).toString('base64');
  return new Promise((resolve) => {
    const req = http.request({
      host,
      port,
      path: '/api/remote.mux',
      headers: {
        Connection: 'Upgrade',
        Upgrade: 'websocket',
        'Sec-WebSocket-Version': '13',
        'Sec-WebSocket-Key': key,
        Cookie: cookie,
        Origin: opt.url.replace(/\/$/, ''),
        'Sec-Fetch-Site': 'same-origin',
        Host: `${host}:${port}`,
      },
    });
    const done = (result) => {
      clearTimeout(timer);
      resolve(result);
    };
    const timer = setTimeout(() => done({ ok: false, detail: 'timeout' }), opt.timeout);
    req.on('upgrade', (res, socket) => {
      socket.destroy();
      done({ ok: res.statusCode === 101, detail: `101 ${res.headers['sec-websocket-accept'] ? 'accept=yes' : 'accept=no'}` });
    });
    req.on('response', (res) => done({ ok: false, detail: `rejected ${res.statusCode}` }));
    req.on('error', (e) => done({ ok: false, detail: e.message }));
    req.end();
  });
}

const cookie = await pair();
if (!cookie) {
  console.log('没有 --pin，跳过认证请求');
  process.exit(1);
}
const auth = { Cookie: cookie };

const indexRes = await request('/', { headers: auth, accept: 'text/html' });
const index = indexRes.body.toString('utf8');
console.log(`index: ${indexRes.status} ${index.length} bytes`);
if (indexRes.status !== 200 || index.length < 2000) {
  console.log('index 不可用，后续检查无意义');
  process.exit(3);
}

const injected = ['viewport-fit=cover', 'apple-mobile-web-app-capable', '/__m/mobile.css', '/__m/mobile.js'];
for (const marker of injected) {
  console.log(`inject ${marker}: ${index.includes(marker) ? 'ok' : 'MISSING'}`);
}

const urls = new Set();
for (const m of index.matchAll(/(?:href|src)="(?:\.\/)?([^"]+)"/g)) {
  const u = m[1];
  if (u.startsWith('assets/') || u.startsWith('plugins/')) urls.add('/' + u.replace(/&amp;/g, '&'));
}
for (const m of index.matchAll(/"url":"(plugins\/[^"]+)"/g)) urls.add('/' + m[1].replace(/&amp;/g, '&'));
for (const extra of ['/manifest.webmanifest', '/apple-touch-icon.png', '/__m/mobile.css', '/__m/mobile.js']) urls.add(extra);

let bytes = 0;
const bad = [];
for (const u of urls) {
  const res = await request(u, { headers: auth });
  bytes += res.body.length;
  if (res.status !== 200 || res.body.length === 0) bad.push({ u, status: res.status, bytes: res.body.length, error: res.error });
}

console.log(`assets: ${urls.size} URLs, ok ${urls.size - bad.length}, bad ${bad.length}, ${(bytes / 1048576).toFixed(2)} MiB`);
for (const b of bad) console.log(`  BAD ${b.u} ${b.status} ${b.bytes} ${b.error || ''}`);

let wsOk = true;
if (opt.ws) {
  const ws = await checkWs(cookie);
  wsOk = ws.ok;
  console.log(`websocket: ${ws.ok ? 'ok' : 'FAIL'} (${ws.detail})`);
}

const pass = bad.length === 0 && wsOk;
console.log(pass ? '\nRESULT: PASS — 手机端可以完整加载这个会话' : '\nRESULT: FAIL');
process.exit(pass ? 0 : 4);
