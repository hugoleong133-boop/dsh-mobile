#!/usr/bin/env node
/**
 * dsh-mobile — 把本机 DSH Web GUI 暴露到局域网/隧道，给 iPhone 当"豆包工作模式"用。
 *
 * 设计约束（来自 DSH 0.2.2-rc.1 实际实现）：
 *  - dsh-host-webserver 只肯绑具体 IP 字面量，`--host 0.0.0.0` 被拒；绑定非回环地址后
 *    client-connection 的 Host/Origin 围栏要求 Host ∈ {loopback, bind IP, trustedHosts}。
 *  - /api 与 Gateway WebSocket 需要已认证的 browser Peer：`GET /?token=` 换 HttpOnly cookie，
 *    cookie 值 = v1.<b64url(payload)>.<HMAC-SHA256(secret, body)>，secret 持久化在
 *    $DSH_HOME/.credentials.yaml 的 client-connection/browser-session 记录里。
 *
 * 因此这里不起第二个 Host，也不碰 DSH 配置：本进程把请求的 Host/Origin 重写回
 * 127.0.0.1:<port>，并用同一份 secret 现场铸造合法 DSH cookie 注入。DSH 侧全程以为
 * 请求来自本机浏览器，围栏与认证都照常生效，无需 patch 任何 DSH 文件。
 *
 * 额外给手机端注入：viewport-fit=cover、apple-mobile-web-app-capable、safe-area 修正 CSS。
 * 入口本身有 PIN 门禁，因为 DSH 的 owner Peer 权限是全量（含 pwsh danger-full-access）。
 */

import http from 'node:http';
import https from 'node:https';
import { execFileSync } from 'node:child_process';
import os from 'node:os';
import path from 'node:path';
import { readFileSync, existsSync, writeFileSync, mkdirSync } from 'node:fs';
import { createHash, createHmac, randomBytes, randomInt, timingSafeEqual } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const HOME = process.env.USERPROFILE || process.env.HOME || '';
const DSH_HOME = process.env.DSH_HOME || path.join(HOME, '.dsh');

// ---------------------------------------------------------------- args

function parseArgs(argv) {
  const out = {
    listen: '0.0.0.0',
    port: 8765,
    upstreamHost: '127.0.0.1',
    upstreamPort: 55514,
    credentials: path.join(DSH_HOME, '.credentials.yaml'),
    stateFile: path.join(HERE, 'state.json'),
    assets: path.join(HERE, 'assets'),
    tlsCert: null,
    tlsKey: null,
    publicUrl: null,
    pin: null,
    cookieDays: 30,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    const next = () => {
      const v = argv[i + 1];
      if (v === undefined) throw new Error(`missing value for ${a}`);
      i += 1;
      return v;
    };
    switch (a) {
      case '--listen': out.listen = next(); break;
      case '--port': out.port = Number(next()); break;
      case '--upstream-host': out.upstreamHost = next(); break;
      case '--upstream-port': out.upstreamPort = Number(next()); break;
      case '--credentials': out.credentials = next(); break;
      case '--state': out.stateFile = next(); break;
      case '--tls-cert': out.tlsCert = next(); break;
      case '--tls-key': out.tlsKey = next(); break;
      case '--public-url': out.publicUrl = next(); break;
      case '--pin': out.pin = next(); break;
      case '--cookie-days': out.cookieDays = Number(next()); break;
      case '--help':
      case '-h':
        process.stdout.write(readFileSync(path.join(HERE, 'server.mjs'), 'utf8').split('*/')[0] + '\n');
        process.exit(0);
        break;
      default:
        throw new Error(`unknown argument: ${a}`);
    }
  }
  return out;
}

const ARGS = parseArgs(process.argv.slice(2));

/**
 * 上游端口是活的：DSH 重启/升级后会换端口（本机实测 55514 → 53212）。
 * 0 表示交给自动发现；发现失败就退回最后一次已知端口。
 */
const UP = {
  host: ARGS.upstreamHost,
  port: ARGS.upstreamPort > 0 ? ARGS.upstreamPort : 0,
  lastGood: ARGS.upstreamPort > 0 ? ARGS.upstreamPort : 0,
  lastProbe: 0,
  lastProbeResult: 0,
};

const autoUpstream = ARGS.upstreamPort <= 0;

function upAuthority() {
  return `${UP.host}:${UP.port}`;
}

function upOrigin() {
  return `http://${upAuthority()}`;
}

// ---------------------------------------------------------------- upstream discovery

const DSH_PROCESS = 'DeepSeek Harness.exe';
const PROBE_COOLDOWN_MS = 3000;
const PROBE_MAX_AGE_MS = 30000;

/** 正在跑的 DSH 进程 PID 列表。tasklist 是 Windows 自带，不需要管理员。 */
function dshPids() {
  try {
    const out = execFileSync(
      'tasklist',
      ['/FI', `IMAGENAME eq ${DSH_PROCESS}`, '/FO', 'CSV', '/NH'],
      { encoding: 'utf8', windowsHide: true, timeout: 8000 },
    );
    const pids = [];
    for (const line of out.split(/\r?\n/)) {
      const m = /^"([^"]+)","(\d+)"/.exec(line.trim());
      if (m && m[1].toLowerCase() === DSH_PROCESS.toLowerCase()) pids.push(Number(m[2]));
    }
    return pids;
  } catch {
    return [];
  }
}

/** 这些 PID 正在 LISTEN 的回环端口。 */
function listenerPorts(pids) {
  try {
    const out = execFileSync('netstat', ['-ano', '-p', 'TCP'], { encoding: 'utf8', windowsHide: true, timeout: 8000 });
    const ports = [];
    for (const line of out.split(/\r?\n/)) {
      const cols = line.trim().split(/\s+/);
      if (cols.length < 5 || cols[0] !== 'TCP') continue;
      if (cols[3] !== 'LISTENING') continue;
      if (!pids.includes(Number(cols[4]))) continue;
      const port = Number(cols[1].slice(cols[1].lastIndexOf(':') + 1));
      if (port > 0) ports.push(port);
    }
    return ports.sort((a, b) => a - b);
  } catch {
    return [];
  }
}

/**
 * 重新发现上游端口。带冷却，避免每个失败请求都 fork 两个进程。
 * 优先沿用上次成功的端口，这样多窗口并存时不会来回跳。
 * @returns 找到的端口，0 表示没找到
 */
function discoverUpstream(force = false) {
  const now = Date.now();
  if (!force && now - UP.lastProbe < PROBE_COOLDOWN_MS) return UP.lastProbeResult;
  UP.lastProbe = now;

  const pids = dshPids();
  if (pids.length === 0) {
    UP.lastProbeResult = 0;
    return 0;
  }
  const ports = listenerPorts(pids);
  if (ports.length === 0) {
    UP.lastProbeResult = 0;
    return 0;
  }
  const chosen = ports.includes(UP.lastGood) ? UP.lastGood : ports[0];
  UP.lastProbeResult = chosen;
  if (chosen !== UP.port) {
    const from = UP.port || '自动';
    UP.port = chosen;
    UP.lastGood = chosen;
    console.log(`[upstream] ${from} -> ${chosen}（DSH 换了监听端口）`);
  }
  return chosen;
}

if (autoUpstream) {
  const found = discoverUpstream(true);
  if (found === 0) {
    console.error('[upstream] 现在没发现监听的 DeepSeek Harness；代理继续跑，收到请求时会再探。');
  }
  // 没有流量时也定期校准一次，别等到用户点开页面才发现端口变了
  setInterval(() => {
    try {
      discoverUpstream(false);
    } catch {
      /* 探测失败不影响服务 */
    }
  }, 30_000).unref();
}



// ---------------------------------------------------------------- DSH cookie

const B64URL = /^[A-Za-z0-9_-]*$/;

function b64u(buf) {
  return Buffer.from(buf).toString('base64').replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/u, '');
}

function unb64u(text) {
  if (!B64URL.test(text)) return undefined;
  const padded = text.replaceAll('-', '+').replaceAll('_', '/') + '='.repeat((4 - (text.length % 4)) % 4);
  const buf = Buffer.from(padded, 'base64');
  return b64u(buf) === text ? buf : undefined;
}

/**
 * 从 .credentials.yaml 里取 browser-session 的 32 字节签名密钥。
 * 文件是 YAML，但结构固定且我们只需要一个字段：定位记录键后取它下面第一个 secret。
 * 解析失败一律抛错——绝不用随机密钥兜底，否则会静默产生永远 401 的 cookie。
 */
function readBrowserSecret(file) {
  const text = readFileSync(file, 'utf8');
  const lines = text.split(/\r?\n/);
  const keyAt = lines.findIndex((line) => /^\s*["']?client-connection\/browser-session["']?\s*:/.test(line));
  if (keyAt === -1) throw new Error(`browser-session record not found in ${file}`);
  const baseIndent = lines[keyAt].search(/\S/);
  for (let i = keyAt + 1; i < lines.length; i += 1) {
    const line = lines[i];
    if (!line.trim()) continue;
    const indent = line.search(/\S/);
    if (indent <= baseIndent) break;
    const m = /^\s*secret\s*:\s*["']?([A-Za-z0-9_-]{43})["']?\s*$/.exec(line);
    if (m) {
      const secret = unb64u(m[1]);
      if (secret === undefined || secret.byteLength !== 32) throw new Error('browser-session secret is not 32 base64url bytes');
      return secret;
    }
  }
  throw new Error('browser-session secret not found');
}

function cookieNameFor(authority) {
  return 'dsh-auth-' + b64u(createHash('sha256').update(authority).digest());
}

function mintDshCookie(secret, days, authority) {
  const now = Date.now();
  const payload = { version: 1, authority, issuedAt: now, expiresAt: now + days * 86400_000 };
  const body = b64u(Buffer.from(JSON.stringify(payload), 'utf8'));
  const sig = b64u(createHmac('sha256', secret).update(body).digest());
  return `${cookieNameFor(authority)}=v1.${body}.${sig}`;
}

const SECRET = readBrowserSecret(ARGS.credentials);

// cookie 绑 authority（= host:port），上游换端口就得重铸，按端口缓存
let cookieCache = { port: 0, value: '' };

function dshCookie() {
  if (cookieCache.port !== UP.port) {
    cookieCache = { port: UP.port, value: mintDshCookie(SECRET, ARGS.cookieDays, upAuthority()) };
  }
  return cookieCache.value;
}

// ---------------------------------------------------------------- local state

function loadState() {
  if (existsSync(ARGS.stateFile)) {
    try {
      const parsed = JSON.parse(readFileSync(ARGS.stateFile, 'utf8'));
      if (typeof parsed.deviceSecret === 'string' && /^[0-9a-f]{64}$/.test(parsed.deviceSecret)) {
        return parsed;
      }
    } catch {
      /* fallthrough: rewrite */
    }
  }
  const state = {
    deviceSecret: randomBytes(32).toString('hex'),
    pin: String(randomInt(100000, 1000000)),
    createdAt: new Date().toISOString(),
  };
  mkdirSync(path.dirname(ARGS.stateFile), { recursive: true });
  writeFileSync(ARGS.stateFile, JSON.stringify(state, null, 2), 'utf8');
  return state;
}

const STATE = loadState();
if (ARGS.pin) {
  STATE.pin = String(ARGS.pin);
  writeFileSync(ARGS.stateFile, JSON.stringify(STATE, null, 2), 'utf8');
}

const DEVICE = Buffer.from(STATE.deviceSecret, 'hex');
const GATE_NAME = 'dshm';
const GATE_VALUE = createHmac('sha256', DEVICE).update('dsh-mobile/v1').digest('hex');

function safeEqual(a, b) {
  const x = Buffer.from(String(a), 'utf8');
  const y = Buffer.from(String(b), 'utf8');
  return x.byteLength === y.byteLength && timingSafeEqual(x, y);
}

function readCookie(header, name) {
  if (!header) return undefined;
  for (const segment of header.split(';')) {
    const at = segment.indexOf('=');
    if (at === -1) continue;
    if (segment.slice(0, at).trim() === name) return segment.slice(at + 1).trim();
  }
  return undefined;
}

function isAuthed(req) {
  const value = readCookie(req.headers.cookie, GATE_NAME);
  return value !== undefined && safeEqual(value, GATE_VALUE);
}

function clientIp(req) {
  return (req.socket.remoteAddress || '').replace(/^::ffff:/, '');
}

// ---------------------------------------------------------------- static assets

const STATIC = new Map([
  ['/__m/mobile.css', { file: 'mobile.css', type: 'text/css; charset=utf-8' }],
  ['/__m/mobile.js', { file: 'mobile.js', type: 'text/javascript; charset=utf-8' }],
  ['/__m/icon-180.png', { file: 'icon-180.png', type: 'image/png' }],
  ['/__m/icon-512.png', { file: 'icon-512.png', type: 'image/png' }],
]);

function sendStatic(req, res, entry) {
  let body;
  try {
    body = readFileSync(path.join(ARGS.assets, entry.file));
  } catch {
    res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
    res.end('missing asset');
    return;
  }
  res.writeHead(200, {
    'content-type': entry.type,
    'content-length': body.byteLength,
    // 调试期间不要缓存：改了 css/js 要能立刻在手机上看到效果
    'cache-control': 'no-cache, no-store, must-revalidate',
  });
  res.end(req.method === 'HEAD' ? undefined : body);
}

// ---------------------------------------------------------------- pairing page

function pairingPage(reason, target) {
  const reasonText = reason === 'bad-pin' ? 'PIN 不对，重新输入。' : '这台设备还没配对上。';
  const action = target && target !== '/' ? `?next=${encodeURIComponent(target)}` : '';
  return `<!doctype html>
<html lang="zh-CN"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-title" content="DSH">
<meta name="apple-touch-icon" href="/__m/icon-180.png">
<meta name="theme-color" content="#151517">
<title>配对 DSH</title>
<style>
*{box-sizing:border-box}
html,body{margin:0;height:100%}
body{background:#151517;color:#e8e8ea;font:16px/1.5 -apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;
 display:flex;align-items:center;justify-content:center;padding:max(24px,env(safe-area-inset-top)) 20px max(24px,env(safe-area-inset-bottom))}
.card{width:100%;max-width:420px}
.logo{width:64px;height:64px;border-radius:16px;background:linear-gradient(140deg,#4b6bff,#8a4bff);margin-bottom:20px}
h1{font-size:22px;margin:0 0 6px}
p{color:#9a9aa2;margin:0 0 22px;font-size:14px}
input{width:100%;font-size:28px;letter-spacing:.3em;text-align:center;padding:14px;border-radius:14px;
 border:1px solid #33333a;background:#1d1d21;color:#fff;font-family:ui-monospace,SFMono-Regular,monospace}
input:focus{outline:2px solid #4b6bff;border-color:transparent}
button{width:100%;margin-top:14px;padding:15px;border:0;border-radius:14px;background:#4b6bff;color:#fff;font-size:17px;font-weight:600}
button:active{opacity:.85}
.err{color:#ff7a7a;font-size:14px;margin-top:14px;min-height:20px}
.hint{margin-top:26px;font-size:13px;color:#71717a;line-height:1.7}
code{background:#26262b;padding:1px 6px;border-radius:5px;font-size:12px}
</style></head>
<body><div class="card">
  <div class="logo"></div>
  <h1>配对这台 iPhone</h1>
  <p>${reasonText}输入电脑上 <code>start.ps1</code> 打印的 6 位 PIN。</p>
  <form method="POST" action="/__m/pin${action}">
    <input name="pin" inputmode="numeric" pattern="[0-9]*" maxlength="6" autocomplete="one-time-code" autofocus placeholder="------">
    <button type="submit">连接</button>
  </form>
  <div class="err">${reason === 'bad-pin' ? 'PIN 校验失败' : ''}</div>
  <div class="hint">配对成功后：Safari 分享按钮 → 「添加到主屏幕」，
  之后从主屏幕图标进入就是全屏 App，和电脑上看到的是同一个会话。</div>
</div></body></html>`;
}

// ---------------------------------------------------------------- HTML injection

function injectHead(html) {
  const extras = [
    '<meta name="apple-mobile-web-app-capable" content="yes">',
    '<meta name="mobile-web-app-capable" content="yes">',
    '<meta name="apple-mobile-web-app-status-bar-style" content="default">',
    '<meta name="apple-mobile-web-app-title" content="DSH">',
    '<meta name="format-detection" content="telephone=no">',
    '<link rel="apple-touch-icon" href="/__m/icon-180.png">',
    '<link rel="stylesheet" href="/__m/mobile.css">',
    '<script src="/__m/mobile.js" defer></script>',
  ].join('');

  const viewport = '<meta name="viewport" content="width=device-width, initial-scale=1, '
    + 'viewport-fit=cover, interactive-widget=resizes-content" />';
  const out = html.replace(/<meta\s+name=["']viewport["'][^>]*>/i, viewport);

  if (/<\/head>/i.test(out)) return out.replace(/<\/head>/i, extras + '</head>');
  return out + extras;
}

// ---------------------------------------------------------------- upstream proxy

function proxyHeaders(req) {
  const headers = {};
  for (const [k, v] of Object.entries(req.headers)) {
    if (v !== undefined) headers[k] = v;
  }
  headers.host = upAuthority();
  if (headers.origin) headers.origin = upOrigin();
  if (headers.referer) headers.referer = String(headers.referer).replace(/^https?:\/\/[^/]+/i, upOrigin());
  headers.cookie = dshCookie();
  headers['accept-encoding'] = 'identity';
  headers['x-forwarded-for'] = clientIp(req);
  headers['x-forwarded-host'] = req.headers.host || '';
  headers['x-forwarded-proto'] = ARGS.tlsCert ? 'https' : 'http';
  return headers;
}

function wantsHtml(req) {
  return req.method === 'GET' || req.method === 'HEAD';
}

function handleProxy(req, res, attempt = 1) {
  const bodyless = req.method === 'GET' || req.method === 'HEAD';
  const canRetry = attempt === 1 && bodyless && autoUpstream;

  if (UP.port === 0) {
    if (discoverUpstream(true) === 0) {
      res.writeHead(503, { 'content-type': 'text/plain; charset=utf-8' });
      res.end('dsh-mobile: 没有发现正在监听的 DeepSeek Harness，先在这台电脑上打开 DSH。\n');
      return;
    }
  }

  const options = {
    host: UP.host,
    port: UP.port,
    method: req.method,
    path: req.url,
    headers: proxyHeaders(req),
    agent: false,
  };

  const upstream = http.request(options, (upRes) => {
    const type = String(upRes.headers['content-type'] || '');
    const isHtml = type.includes('text/html');

    if (!isHtml) {
      res.writeHead(upRes.statusCode || 502, upRes.headers);
      upRes.pipe(res);
      return;
    }

    const chunks = [];
    upRes.on('data', (c) => chunks.push(c));
    upRes.on('end', () => {
      let html = Buffer.concat(chunks).toString('utf8');
      html = injectHead(html);
      const body = Buffer.from(html, 'utf8');
      const headers = { ...upRes.headers };
      delete headers['content-encoding'];
      delete headers['content-length'];
      // 上游是 chunked；注入后我们给出确切长度，两者不能同时出现
      delete headers['transfer-encoding'];
      delete headers.etag;
      headers['content-length'] = body.byteLength;
      headers['cache-control'] = 'no-store';
      res.writeHead(upRes.statusCode || 200, headers);
      res.end(req.method === 'HEAD' ? undefined : body);
    });
  });

  upstream.on('error', (err) => {
    if (res.headersSent) {
      res.destroy();
      return;
    }

    // DSH 重启换了端口时，老端口是 ECONNREFUSED。GET/HEAD 无副作用，重探一次再打。
    if (canRetry && (err.code === 'ECONNREFUSED' || err.code === 'EHOSTUNREACH' || err.code === 'ECONNRESET')) {
      const before = UP.port;
      const found = discoverUpstream(true);
      if (found > 0 && found !== before) {
        handleProxy(req, res, attempt + 1);
        return;
      }
    }

    res.writeHead(502, { 'content-type': 'text/plain; charset=utf-8' });
    res.end(`dsh-mobile: upstream ${upAuthority()} failed — ${err.message}\n`);
  });

  if (bodyless) upstream.end();
  else req.pipe(upstream);
}

// ---------------------------------------------------------------- HTTP entry

function handle(req, res) {
  let url;
  try {
    url = new URL(req.url, `http://${req.headers.host || 'dsh.local'}`);
  } catch {
    res.writeHead(400).end();
    return;
  }
  const pathname = url.pathname;

  const staticEntry = STATIC.get(pathname);
  if (staticEntry) {
    sendStatic(req, res, staticEntry);
    return;
  }

  // 免认证的自检端点：人在外网时用来判断到底是代理挂了还是 DSH 挂了。
  // 只暴露端口与进程计数，不含 PIN、不含 cookie、不含密钥。
  if (pathname === '/__m/status') {
    // 先自愈：DSH 换端口后，第一个来查状态的请求就把上游纠正过来
    let pids = dshPids();
    let ports = listenerPorts(pids);
    if (UP.port !== 0 && !ports.includes(UP.port)) {
      discoverUpstream(true);
      pids = dshPids();
      ports = listenerPorts(pids);
    }
    const payload = {
      ok: ports.length > 0 && ports.includes(UP.port),
      proxy: { port: ARGS.port, listen: ARGS.listen, tls: Boolean(ARGS.tlsCert) },
      upstream: {
        authority: upAuthority(),
        port: UP.port,
        auto: autoUpstream,
        dshProcesses: pids.length,
        dshListening: ports,
      },
      uptimeSeconds: Math.round(process.uptime()),
    };
    res.writeHead(200, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
    res.end(JSON.stringify(payload, null, 2));
    return;
  }

  if (pathname === '/__m/pin' && req.method === 'POST') {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      const body = new URLSearchParams(Buffer.concat(chunks).toString('utf8'));
      const pin = String(body.get('pin') || '').trim();
      const next = String(body.get('next') || url.searchParams.get('next') || '/');
      const dest = next.startsWith('/') && !next.startsWith('//') ? next : '/';
      if (!safeEqual(pin, STATE.pin)) {
        res.writeHead(401, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' });
        res.end(pairingPage('bad-pin', dest));
        return;
      }
      const attrs = [
        `${GATE_NAME}=${GATE_VALUE}`,
        `Max-Age=${String(180 * 86400)}`,
        'Path=/',
        'HttpOnly',
        'SameSite=Lax',
      ];
      if (ARGS.tlsCert) attrs.push('Secure');
      console.log(`[pair] ${clientIp(req)} -> ${dest}`);
      res.writeHead(303, { 'set-cookie': attrs.join('; '), location: dest });
      res.end();
    });
    return;
  }

  // 允许直接用 ?k=<pin> 配对（二维码/手输链接）
  const queryPin = url.searchParams.get('k');
  if (queryPin !== null && safeEqual(queryPin, STATE.pin)) {
    const attrs = [`${GATE_NAME}=${GATE_VALUE}`, `Max-Age=${String(180 * 86400)}`, 'Path=/', 'HttpOnly', 'SameSite=Lax'];
    if (ARGS.tlsCert) attrs.push('Secure');
    url.searchParams.delete('k');
    const dest = url.pathname + (url.searchParams.toString() ? `?${url.searchParams.toString()}` : '');
    res.writeHead(303, { 'set-cookie': attrs.join('; '), location: dest });
    res.end();
    return;
  }

  if (!isAuthed(req)) {
    const accept = String(req.headers.accept || '');
    if (wantsHtml(req) && accept.includes('text/html')) {
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' });
      res.end(req.method === 'HEAD' ? undefined : pairingPage('none', pathname));
      return;
    }
    res.writeHead(401, { 'content-type': 'text/plain; charset=utf-8' });
    res.end('dsh-mobile: pairable device required\n');
    return;
  }

  handleProxy(req, res);
}

// ---------------------------------------------------------------- WebSocket upgrade

function serializeHandshake(res) {
  const lines = [`HTTP/1.1 ${res.statusCode} ${res.statusMessage || 'Switching Protocols'}`];
  for (const [k, v] of Object.entries(res.headers)) {
    if (v === undefined) continue;
    if (Array.isArray(v)) for (const item of v) lines.push(`${k}: ${item}`);
    else lines.push(`${k}: ${v}`);
  }
  return lines.join('\r\n') + '\r\n\r\n';
}

function handleUpgrade(req, clientSocket, head) {
  clientSocket.on('error', () => clientSocket.destroy());

  if (!isAuthed(req)) {
    clientSocket.end('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\nContent-Length: 0\r\n\r\n');
    return;
  }

  const upstream = http.request({
    host: ARGS.upstreamHost,
    port: UP.port,
    method: req.method,
    path: req.url,
    headers: proxyHeaders(req),
    agent: false,
  });

  upstream.on('upgrade', (upRes, upSocket, upHead) => {
    clientSocket.write(serializeHandshake(upRes));
    if (upHead && upHead.length) clientSocket.write(upHead);
    upSocket.on('error', () => clientSocket.destroy());
    clientSocket.on('error', () => upSocket.destroy());
    upSocket.pipe(clientSocket);
    clientSocket.pipe(upSocket);
  });

  upstream.on('response', (upRes) => {
    clientSocket.write(serializeHandshake(upRes));
    upRes.pipe(clientSocket);
  });

  upstream.on('error', (err) => {
    console.log(`[ws] upstream error: ${err.message}`);
    clientSocket.destroy();
  });

  if (head && head.length) upstream.write(head);
  upstream.end();
}

// ---------------------------------------------------------------- boot

function localAddresses() {
  const out = [];
  const interfaces = os.networkInterfaces();
  for (const [name, addrs] of Object.entries(interfaces)) {
    for (const addr of addrs || []) {
      if (addr.family !== 'IPv4' || addr.internal) continue;
      out.push({ name, address: addr.address });
    }
  }
  return out;
}

function banner(protocol) {
  const lines = [];
  lines.push('');
  lines.push('  DSH Mobile  ·  手机 ↔ 这台电脑的同一个会话');
  lines.push('  ' + '─'.repeat(58));
  const urls = [];
  if (ARGS.publicUrl) urls.push(ARGS.publicUrl);
  for (const { name, address } of localAddresses()) {
    urls.push(`${protocol}//${address}:${ARGS.port}/?k=${STATE.pin}`);
    lines.push(`  ${name.padEnd(14)} ${protocol}//${address}:${ARGS.port}/?k=${STATE.pin}`);
  }
  lines.push(`  本机            ${protocol}://127.0.0.1:${ARGS.port}/?k=${STATE.pin}`);
  lines.push('  ' + '─'.repeat(58));
  lines.push(`  PIN             ${STATE.pin}`);
  lines.push(`  上游            ${upAuthority()}`);
  lines.push(`  状态文件        ${ARGS.stateFile}`);
  lines.push('');
  lines.push('  iPhone：Safari 打开上面任一手机地址 → 分享 → 添加到主屏幕');
  lines.push('');
  writeFileSync(path.join(HERE, 'pair-url.txt'), urls.join('\n') + '\n', 'utf8');
  process.stdout.write(lines.join('\n') + '\n');
}

const server = ARGS.tlsCert
  ? https.createServer(
    { cert: readFileSync(ARGS.tlsCert), key: readFileSync(ARGS.tlsKey) },
    handle,
  )
  : http.createServer(handle);

server.on('upgrade', handleUpgrade);
server.on('connection', (socket) => {
  // 手机切网络、锁屏都会半路中止连接；未监听的 'error' 会直接杀死整个守护进程
  socket.on('error', () => {});
});
server.on('clientError', (err, socket) => {
  if (socket.writable) socket.end('HTTP/1.1 400 Bad Request\r\n\r\n');
});
process.on('uncaughtException', (err) => {
  console.error(`[fatal] ${err && err.stack ? err.stack : err}`);
});

server.listen(ARGS.port, ARGS.listen, () => {
  banner(ARGS.tlsCert ? 'https' : 'http');
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => {
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 500).unref();
  });
}
