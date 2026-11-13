// dsh-mobile supervisor
//
// 为什么需要它：代理（server.mjs）是普通 node 进程，电脑睡眠/唤醒、系统更新
// 都可能把它静默杀掉，且不留任何日志。手机端表现是三条通道同时超时（-1001）。
//
// watchdog.ps1 那种「每 2 分钟启动一次 powershell」的做法有个副作用：
// 每次启动都会闪一下控制台窗口。所以改成常驻进程——
// 只在开机时启动一次，之后由它守着代理，代理退出就立刻重启。
//
// watchdog.ps1 仍然保留，但只作为兜底（低频检查这个 supervisor 是否还活着）。

import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const PORT = process.env.DSHM_PORT || '8765';

const certPath = path.join(HERE, 'certs', 'server.crt');
const keyPath = path.join(HERE, 'certs', 'server.key');
const hasTLS = existsSync(certPath) && existsSync(keyPath);

// start.ps1 会把完整参数（--port / --state / --pin / --tls-cert …）传进来，原样透传；
// 单独运行本脚本时才用默认值，方便手工排查。
const passthrough = process.argv.slice(2);
const serverArgs = [path.join(HERE, 'server.mjs'), ...passthrough];
if (passthrough.length === 0) {
  serverArgs.push('--port', PORT);
  if (hasTLS) {
    serverArgs.push('--tls-cert', certPath, '--tls-key', keyPath);
  }
}

let child = null;
let stopping = false;
let restarts = 0;

function stamp() {
  return new Date().toISOString().replace('T', ' ').slice(0, 19);
}

function start() {
  child = spawn(process.execPath, serverArgs, {
    cwd: HERE,
    stdio: 'inherit',
    windowsHide: true,
  });

  child.on('exit', (code, signal) => {
    if (stopping) return;
    restarts += 1;
    console.log(`[supervisor ${stamp()}] 代理退出 code=${code} signal=${signal}，第 ${restarts} 次重启`);
    setTimeout(start, 2000);
  });

  child.on('error', (err) => {
    console.error(`[supervisor ${stamp()}] 启动失败: ${err.message}`);
    setTimeout(start, 5000);
  });
}

function shutdown() {
  stopping = true;
  if (child && !child.killed) child.kill();
  setTimeout(() => process.exit(0), 300);
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

console.log(`[supervisor ${stamp()}] 启动，端口 ${PORT}，TLS=${hasTLS ? 'on' : 'off'}`);
start();
