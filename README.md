# dsh-mobile · 把 DSH 变成手机能看能指挥的「工作模式」

豆包那个能力拆开是三件事：**同一份会话**、**两端都能看到当前进度**、**指令从手机下、活在本机干**。
DSH 本身已经有前两件（会话和 live 事件都挂在同一个 Host 上），缺的只是**让第二台设备能够合法接进来**。

这个目录补的就是那一块：给正在运行的 DSH 套一层带门禁的反向代理，再给手机端注入主屏幕 App 所需的标签。
不修改 DSH 任何文件，不改 profile，不重启 App。

---

## 1. 为什么不能直接 `dsh web --host 0.0.0.0`

读过 `@deepseek-ai/dsh-host-webserver` 与 `dsh-client-connection` 的实现，三条硬约束决定了做法：

| 约束 | 代码位置 | 后果 |
|---|---|---|
| `host` 只接受具体 IP 字面量，未指定地址直接拒绝加载 | `dsh-host-webserver` config schema | 没有「监听所有网卡」这个选项 |
| `/api` 每个请求先过 Host/Origin 围栏：Host 必须是 loopback、监听器绑定 IP、或 `trustedHosts` 条目 | `client-connection/lib/index.js:240 isTrustedApiRequest` | 改绑局域网 IP 后，`127.0.0.1` 反而会被 403 |
| Gateway WebSocket 与 RPC 都要求已认证的 browser Peer；令牌是**每进程随机**，只在 `dsh web` 启动时打印一次 | `BrowserAuth`、`launchToken` | 第二台设备没有途径拿到那个 token |

另有一条可用线索：浏览器会话 cookie 不是随机串，而是
`v1.<b64url(payload)>.<HMAC-SHA256(secret, body)>`，payload 里绑 `authority`（HTTP 下就是 `host:port`），
`secret` 持久化在 `$DSH_HOME/.credentials.yaml` 的 `client-connection/browser-session` 记录里。

于是最干净的接法出现了：**代理把 Host/Origin 重写回 `127.0.0.1:<port>`，并用同一份 secret 现场铸造 cookie 注入。**
DSH 全程以为请求来自本机浏览器，围栏和认证一个都没绕过，也不需要 patch 任何东西。

```
iPhone Safari ──► dsh-mobile:8765 ──► 127.0.0.1:55514 (DSH Web GUI)
   ① PIN 换 dshm cookie        ② Host/Origin 重写 + 注入 dsh-auth cookie
   ③ index 注入主屏幕 App 标签   ④ WebSocket 原样透传
```

---

## 2. 三步跑起来

```powershell
cd D:\Ai\DSH\腳本\dsh-mobile

# 1) 放行防火墙（只有这一步要管理员；Windows 通常也会自己弹窗问）
.\firewall.ps1 -Port 8765

# 2) 起代理（前台；加 -Background 变常驻）
.\start.ps1 -Qr
```

输出：

```
  手机打开： http://192.168.1.10:8765/?k=123456
  PIN：      123456
```

3. iPhone 上：**Safari** 打开那个地址（或扫 `pairing-qr.png`）→ 点「连接」→ 分享按钮 → **添加到主屏幕**。

从主屏幕图标进去就是全屏，没有地址栏，和电脑上看到的是**同一个会话的实时状态**：
电脑在跑的工具调用、流式输出，手机上同步在滚；手机上发的话直接进这台电脑正在跑的会话。

停止：`.\stop.ps1`。

---

## 3. 手机端到底能做什么

一句话：**手机连的是同一个 DSH 实例、同一个会话**，不是镜像、不是副本。所以电脑上跑的任务，手机上能看到并接管；手机上发的指令，进的就是公司电脑上那个正在跑的 agent。

| 能力 | 能吗 | 依据 |
|---|---|---|
| 看到电脑上所有会话（含哪个在跑） | ✅ | 经代理调 `session/list` 实测：13 个会话，`running=true` 正确 |
| 看到当前会话的正文 | ✅ | `session/page` 实测：17 条记录 / 34,716 字节，cursor 1614 |
| 看到实时状态（队列、是否在跑） | ✅ | `session/state` 实测：`{cursor:1560, running:true, queue:[]}` |
| 实时流式输出、工具调用卡片 | ✅ | WebSocket `/api/remote.mux` 公网 101 + 服务端帧；投递由 DSH 客户端自身完成 |
| 发指令 / 发任务 | ✅ | `session/prompt` 与上面几个端点同一条 `/api` 通道、同一个 owner Peer |
| 中途插话、取消 | ✅ | `session/prompt`（追加）+ `session/cancel` |
| 审批弹窗、反问（ask_user_question） | ✅ | owner Peer 的 `interactions` 默认 `answer`；非 owner 才被限（`remote-access` README:87） |
| 上传附件给会话 | ✅ | 落在**电脑**的附件目录 |
| 浏览/下载电脑上的文件 | 走同一套客户端 bundle | 端点是 `workspaceFiles/list`、`/read`、`/stat`，需要 UI 生成的 scope id；这里没构造出合法 scope，未实测，但手机加载的是与桌面同一份前端代码 |
| 关掉手机后任务继续跑 | ✅ | agent 在电脑进程里，手机断连不影响 |
| 手机锁屏后再打开能追平进度 | 靠 DSH 自身的重连 + 基线 | `ConnectionController` 500ms→10s 退避重连、`ready` 帧后按 cursor 补齐；长时间睡眠未实测 |

为什么手机有 owner 权限：`dsh-client-connection` 里 `browserPeer = new Peer(ctx, { principal: { kind: "owner" } })` —— 所有通过浏览器令牌认证的连接共用一个 owner Peer。代理铸造的就是这个令牌，所以手机 = 第二个 owner 端。

**因此有一个副作用要记住**：两端同时输入会进同一个会话队列；两端都能点审批——谁先点生效。

---

## 4. 关于 IPA


直接说清楚：**iOS 二进制必须在 macOS 上编译**（`xcodebuild` 只存在于 Xcode）。这台机器是 Windows，
所以我没法在这里产出一个 `.ipa` 文件本身。给你的是两条都能拿到东西的路：

### A. 主屏幕 App（推荐，30 秒，无需签名、永不过期）

DSH 的 Web GUI 自带 `manifest.webmanifest`（`display: standalone`）和 `apple-touch-icon`，
代理又注入了 `apple-mobile-web-app-capable`、`viewport-fit=cover`、安全区 CSS。
Safari「添加到主屏幕」之后：独立窗口、无地址栏、自己图标、保留会话 cookie 30 天。

功能上和下面那个 IPA 是同一份东西——因为 IPA 里包的也是这个页面。

### B. 真 IPA（`ios/` 已备好完整工程）

```powershell
# 把 dsh-mobile 整个目录推到一个 GitHub 仓库（私有也行）
git init; git add -A; git commit -m "dsh-mobile"; git remote add origin <你的仓库>; git push -u origin main
```

然后仓库页面 → **Actions** → `build-ipa` → **Run workflow**。
macOS runner 会执行 `xcodegen generate` + `xcodebuild`（`CODE_SIGNING_ALLOWED=NO`），
把 `DSHMobile.app` 打成 `Payload/` 再 zip 成 **未签名 IPA**，挂在 Artifacts 里。

实测已经跑通，产物就是这个目录下的 `DSHMobile-unsigned.ipa`（69 KB，1m01s 构建）：

```
Payload/DSHMobile.app/DSHMobile      Mach-O 64-bit, cputype 0x100000c (arm64), MH_EXECUTE
Payload/DSHMobile.app/Info.plist     CFBundleIdentifier=local.dshm.mobile, MinimumOSVersion=16.0
                                     NSAppTransportSecurity.NSAllowsArbitraryLoads=true
Payload/DSHMobile.app/Assets.car     AppIcon 已编译进资源目录
_CodeSignature                       不存在（未签名，装之前必须重签）
```

两个踩过的坑，写在这里省一次排查：

| 现象 | 原因 | 处理 |
|---|---|---|
| 作业 1 秒被 cancelled，注解写 `The configuration 'macos-14-arm64-us-default' is not supported` | **免费账户的私有仓库不提供 macOS runner**（只有 Linux） | 仓库设为 public；或升级付费计划 |
| 仓库已公开但 `macos-14` 仍不可用 | 该标签在这账号下解析到不可用的 arm64 配置 | 改用 `macos-15`；`macos-15-intel` 也可用 |

拿到 `DSHMobile-unsigned.ipa` 后，二选一装进 iPhone 15：

| 方式 | 需要 | 有效期 |
|---|---|---|
| **Sideloadly**（省事） | Windows PC + Apple ID，把 ipa 拖进去点 Start | 免费账号 7 天，到期重签 |
| **zsign 手动签** | `.p12` + `.mobileprovision` | 看证书 |

```powershell
.\sign-windows.ps1 -Ipa DSHMobile-unsigned.ipa -P12 cert.p12 -P12Password 123456 -Provision profile.mobileprovision
```

`ios/` 里的壳做了三件事：记住配对地址、WKWebView 加载、`NSAllowsArbitraryLoads`（局域网是 http，ATS 默认会拦）。
业务逻辑一行都没有——真正的 agent 始终跑在电脑上。

---

## 5. 实测结果

在这台机器上跑过的验收（`tests/health.mjs`，走局域网 IP，等价于手机的加载路径）：

```
pair: ok (dshm set)
index: 200 41964 bytes
inject viewport-fit=cover: ok
inject apple-mobile-web-app-capable: ok
inject /__m/mobile.css: ok
inject /__m/mobile.js: ok
assets: 89 URLs, ok 89, bad 0, 20.91 MiB
websocket: ok (101 accept=yes)

RESULT: PASS — 手机端可以完整加载这个会话
```

复现：

```powershell
node tests\health.mjs --url http://192.168.1.10:8765 --pin <PIN>
```

其它已验证的边界：

| 场景 | 结果 |
|---|---|
| 未配对访问 `/` | 200，返回配对页 |
| `?k=<PIN>` | 303 + `Set-Cookie: dshm=…; HttpOnly; SameSite=Lax`，跳回干净 URL |
| 错误 PIN | 401 |
| 无 `dshm` cookie 打 `/api/*` | 401（代理层就挡住，不触达 DSH） |
| 伪造 `dshm` cookie 打 WebSocket | 401 |
| 有效 cookie 打 WebSocket | **101**，随后收到 DSH 的 ping 帧 |
| 静态资源穿透 | `/assets/*`、`/plugins/??…`、`/manifest.webmanifest`、`/apple-touch-icon.png` 全部 200 |
| 手机中途断连 | 已加 socket error 兜底，守护进程不再被 ECONNRESET 打死 |

---

## 6. 安全边界

这个代理握着的是 **DSH owner Peer**，权限等于本机全量（含 `pwsh` 的 danger-full-access）。
所以设计上做了三层：

1. **PIN 门禁**：6 位数字在代理层校验，只换 `dshm` HttpOnly cookie；PIN 与设备密钥存在 `state.json`，重启不变。
2. **只在本机回环上认证 DSH**：DSH 侧看到的永远是 `127.0.0.1:55514`，它自己的围栏（DNS rebinding、跨站）继续生效。
3. **防火墙只放专用/域网络**：`firewall.ps1` 不对公用网络开端口。

`state.json` 里有 `deviceSecret`，`mint_dsh_cookie.py` 那类工具能直接铸造 DSH cookie —— 这两个文件按私钥对待，别进仓库。

---

## 7. 跨网络：在家操作公司电脑

**不需要同一个 WiFi。** 代理监听 `0.0.0.0`，缺的从来不是「同一局域网」，而是一条能把流量送到公司电脑的路径。而且方向很关键：公司防火墙拦的是**入站**，所有可行方案都是**出站**连接。

### 7.1 先判断公司给的是哪种「静态 IP」

这两种意思完全相反，别混：

| 说法 | 实际含义 | 对跨网络有用吗 |
|---|---|---|
| 公司给电脑固定 **192.168.x.x** | 静态**内网** IP，DHCP 保留地址 | ❌ 公网不可路由，端口映射也救不了 |
| 公司有固定**公网** IP（专线） | IP 在路由器 WAN 口或本机网卡 | ✅ 才有可能被外面直接连 |

跑一次就知道：

```powershell
.\probe-network.ps1          # 人话版
.\probe-network.ps1 -Json    # 机器可读
```

它输出本机所有 IPv4（区分 private / public / CGNAT）、出口公网 IP 与归属、443 与 DNS 出站是否通，然后给判定：`public-direct` / `nat` / `cgnat`。

### 7.2 三条路线

| 路线 | 需要什么 | 公司 IT 要不要配合 | 域名稳定性 |
|---|---|---|---|
| **tailscale** | 两边装客户端、登同一账号 | 不要（纯出站） | 固定（MagicDNS 名不变） |
| **cloudflared** | 单个 exe，免安装、免管理员 | 不要（纯出站 443） | quick tunnel 每次重启换域名 |
| **ssh -R** | 家里有公网 IP / IPv6 / 常开 NAS | 不要 | 固定（你自己的域名/IP） |
| 端口映射 | 路由器归你管 + 真·公网 IP | **要** | 固定，但把服务裸露在公网 |

一条命令起步：

```powershell
# 自动挑一个已装的工具（tailscale → cloudflared → ngrok）
.\tunnel.ps1 -Mode auto

# 什么都没装、又不方便安装：拉单文件，纯用户态运行
.\tunnel.ps1 -Mode cloudflare -Download

# 家里有公网 IP / IPv6：公司主动连回家
.\tunnel.ps1 -Mode ssh -SshTarget me@home.example.com

# 人在家里打不开时，先看是哪一头挂了
.\tunnel.ps1 -Mode status
```

### 7.3 这条链路我实测过

在真实公网隧道上跑完整流程（cloudflared quick tunnel，本机 → Cloudflare → 回来）：

```
1) 未配对访问公网地址     200，返回配对页
2) 公网 + PIN 换 cookie   303 + Set-Cookie: dshm=…; HttpOnly; SameSite=Lax
3) 带 cookie 取 index     200 42203 bytes
   viewport-fit=cover: True   apple-mobile-web-app-capable: True
   /__m/mobile.css: True      __DSH_BOOT__: True
4) WebSocket              101 upgrade（over public https）+ 服务端 ping 帧
5) /__m/status            ok=true, upstream 127.0.0.1:53212
```

第 4 条是关键：**进度同步走的就是这条 WebSocket**，公网 101 打通，说明「家里看电脑上的实时进度」成立。测完立刻杀了隧道（Cloudflare 侧回 502，源站已消失）。

### 7.4 公司电脑没人值守时要处理的三件事

```powershell
# 1) 登录自启（当前用户，不需要管理员）；会把 DSH 一起拉起来
.\install-task.ps1
.\install-task.ps1 -Status
.\install-task.ps1 -Remove

# 2) 别让它睡眠，否则隧道和代理一起断
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0

# 3) DSH 重启会换端口（实测 55514 → 53212），代理现在自动跟随
```

第 3 条以前是硬伤：笔记本/公司电脑上 DSH 一更新，代理就连着旧端口，人在家里只能干看着。现在 `server.mjs` 用 `tasklist` + `netstat` 找到 `DeepSeek Harness.exe` 真正监听的端口，启动时探一次，请求失败（`ECONNREFUSED`）时再探一次并重放 GET/HEAD。POST 不重放——它可能有副作用，让 DSH 自己的 RPC 重试逻辑处理。

自检：`curl http://127.0.0.1:8765/__m/status`，看 `upstream.port` 与 `upstream.dshListening` 是否一致。

### 7.5 安全边界（跨网络后才真正要紧）

- 代理握着的是 **DSH owner Peer**，权限等于本机全量（含 `pwsh` 的 danger-full-access）。一条公网 URL + 6 位 PIN，等于把工作站挂在互联网上。
- 所以：**优先 tailscale / ssh**，它们不对公网开放端口；用 cloudflared 时务必开着就开、用完就关，别让它常驻。
- 隧道域名变了就要重新配对（`dshm` cookie 是 host-only）。`/__m/status` 特意做成免认证，只吐端口和进程数，不含 PIN、cookie、密钥。

---

### 7.6 换个网络，地址会变吗

会。四种地址各管一种场合，手机里填哪个决定你以后要不要反复改：

| 地址类型 | 示例 | 在家能用 | 在外/公司能用 | 稳定性 |
|---|---|---|---|---|
| 局域网 IP | `192.168.1.124:8765` | 能 | 不能，出门即失效 | 固定，但只在本网 |
| **tailscale MagicDNS** | `dsh-pc.tailxxxx.ts.net:8765` | 能 | 能 | **固定，配一次长期有效** |
| cloudflared quick tunnel | `xxx-yyy.trycloudflare.com` | 能 | 能 | 每次重启换域名，要重新配对 |
| cloudflared named tunnel | `dsh.你的域名.com` | 能 | 能 | 固定（要自己的域名 + 配置） |

**结论：想「在家连公司电脑」又不想到处改地址，就用 tailscale，并且一开始就拿 tailnet 地址去配对。**
那个地址跟地理位置无关 —— 公司电脑在线，你在家、在咖啡厅、用 4G 访问的都是同一个 URL。

配错也不致命：换地址只是让浏览器重新存一次 cookie，6 位 PIN 不变，App 里点「⋯」→ 重新配对输一次即可。

`start.ps1` 检测到 tailscale 在运行时会把两个地址都打印出来，拿绿色的那个去配对：

```
  任何网络都能用（tailscale，推荐拿这个去配对）：
    http://dsh-pc.tailxxxx.ts.net:8765/?k=123456

  仅同一局域网（换网络就失效）：
    http://192.168.1.10:8765/?k=123456
  PIN：      123456
```

---

## 8. 排错

| 现象 | 原因 / 处理 |
|---|---|
| 手机打不开，电脑上 `curl` 自己 LAN IP 正常 | 防火墙入站未放行：`.\firewall.ps1 -Port 8765` |
| 配对页一直转、点连接没反应 | 端口 8765 被别的进程占了，`-Port 8766` 换一个 |
| 打开了但白屏 | 先跑 `tests\health.mjs`；若 `assets` 有 bad 项，看是不是 DSH 换了 rev（重启 DSH 后 rev 变，属正常） |
| `401 dsh web authentication required` | 代理没读到 `.credentials.yaml`；确认 DSH 至少启动过一次，或 `--credentials` 指对 |
| 手机上看不到电脑上正在跑的对话 | 两端是不是连的同一个 DSH 实例；代理 `--upstream-port` 要等于 DSH 实际监听端口 |
| 后台进程莫名消失 | 它被启动它的那个终端带走了；用 `.\start.ps1 -Background` 起，别用 `Start-Job` |

---

## 9. 文件清单

| 文件 | 作用 |
|---|---|
| `server.mjs` | 代理本体：PIN 门禁、cookie 铸造、Host/Origin 重写、HTML 注入、WebSocket 透传、上游端口自动跟随 |
| `assets/mobile.css` `assets/mobile.js` | 注入到 DSH 页面的安全区/键盘/双击缩放修正 |
| `assets/icon-*.png` | 主屏幕图标 |
| `start.ps1` `stop.ps1` | 起停，自动探测 DSH 端口、局域网 IP、生成 PIN 与二维码 |
| `firewall.ps1` | 放行入站端口（需管理员） |
| `probe-network.ps1` | 判定公网直连 / NAT / CGNAT，给出该走哪条隧道 |
| `tunnel.ps1` | 跨网络通道：tailscale / cloudflared / ngrok / ssh -R，附 `-Mode status` 排障 |
| `boot.ps1` `install-task.ps1` | 无人值守：先拉起 DSH，再起代理；注册成登录自启任务 |
| `sign-windows.ps1` | 把未签名 IPA 用 zsign 重签 |
| `ios/` | SwiftUI + WKWebView 壳工程（XcodeGen 描述） |
| `.github/workflows/build-ipa.yml` | macOS runner 编译并产出未签名 IPA |
| `tests/health.mjs` | 端到端自检：配对 → index → 89 个模块 URL → WebSocket |
| `state.json` | PIN 与设备密钥（敏感） |
