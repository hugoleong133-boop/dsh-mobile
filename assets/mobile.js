/*
 * dsh-mobile 注入脚本。
 * 不 hook DSH 的 store，不拦截 fetch——只补浏览器环境缺的那几块：
 *   1. 标记"独立窗口"，让 CSS 挂安全区（Safari 主屏幕 与 App 内 WKWebView 都要判）
 *   2. visualViewport 高度同步，键盘弹起时输入框不被遮
 *   3. 从后台恢复时触发一次 DSH 自己的重连（它监听 online 事件）
 *   4. 布局探针：找出横向越界的元素并回报给电脑，用于定位窄屏适配问题
 */
(() => {
  const root = document.documentElement;

  // 诊断：页面里每次调用 confirm/alert/prompt 都回报电脑（只记录，不改变行为）。
  // 用来判断「删除会话没反应」到底是 confirm 没被调，还是弹窗没显示。
  if (!window.__dshmDialogHooked) {
    window.__dshmDialogHooked = true;
    const report = (kind, text) => {
      try {
        fetch('/__m/diag', {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({
            type: 'dialog',
            kind,
            text: String(text).slice(0, 300),
            href: location.href,
            ts: Date.now(),
          }),
          credentials: 'same-origin',
        }).catch(() => {});
      } catch { /* 上报失败不影响页面 */ }
    };
    const origConfirm = window.confirm;
    window.confirm = function (msg) {
      report('confirm', msg);
      return origConfirm.apply(this, arguments);
    };
    const origAlert = window.alert;
    window.alert = function (msg) {
      report('alert', msg);
      return origAlert.apply(this, arguments);
    };
    const origPrompt = window.prompt;
    if (origPrompt) {
      window.prompt = function (msg, def) {
        report('prompt', msg);
        return origPrompt.apply(this, arguments);
      };
    }
  }

  // Safari「添加到主屏幕」时 navigator.standalone === true；
  // App 里的 WKWebView 里它是 undefined，只能靠 window.webkit 区分——
  // 之前漏了这条判断，导致 App 内安全区 CSS 一直没生效。
  const inWebView = !!(window.webkit && window.webkit.messageHandlers);
  const standalone = window.navigator.standalone === true
    || (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches);

  if (inWebView) root.dataset.dshmWebview = '1';
  if (standalone || inWebView) root.dataset.dshmStandalone = '1';

  const vv = window.visualViewport;
  if (vv) {
    const sync = () => {
      root.style.setProperty('--dshm-viewport-height', `${Math.round(vv.height)}px`);
      const shrunk = vv.height + 80 < window.innerHeight;
      if (shrunk) root.dataset.dshmKeyboard = '1';
      else delete root.dataset.dshmKeyboard;
    };
    vv.addEventListener('resize', sync, { passive: true });
    vv.addEventListener('scroll', sync, { passive: true });
    sync();
  }

  // 手机切回前台时套接字多半已断，DSH 的 ConnectionController 听 online 才立刻重试，
  // 但 iOS 从后台恢复不一定派发 online，这里补一次。
  const wake = () => {
    if (document.visibilityState !== 'visible') return;
    if (window.navigator.onLine === false) return;
    window.dispatchEvent(new Event('online'));
    window.dispatchEvent(new Event('focus'));
  };
  document.addEventListener('visibilitychange', wake, { passive: true });
  window.addEventListener('pageshow', (event) => {
    if (event.persisted) wake();
  });

  // 双击缩放会让长会话页抖，禁掉 dblclick 缩放但保留双指缩放
  let lastTouch = 0;
  document.addEventListener('touchend', (event) => {
    const now = Date.now();
    if (now - lastTouch <= 300 && event.touches.length === 0) event.preventDefault();
    lastTouch = now;
  }, { passive: false });

  // ---------------------------------------------------------------- 会话删除兜底
  //
  // dsh-session-delete-cascade 的流程是：
  //   POST /session-delete-cascade/plan  →  window.confirm(...)  →  POST /delete
  // WKWebView 里原生 confirm 若不可用会同步返回 false，插件立刻 return，
  // 表现就是「点了没反应」。这里在页面层直接接管这个按钮：
  // 自己弹确认框、自己调 plan/delete，完全不依赖 App 的原生弹窗能力。
  //
  // mobile.js 由代理注入，改完刷新页面即可生效，不需要重装 App。

  const CASCADE_ATTR = 'data-dsh-cascade-delete';
  const CASCADE_BASE = '/session-delete-cascade';

  async function cascadePost(path, body) {
    const response = await fetch(new URL(CASCADE_BASE + path, window.location.origin).toString(), {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(body || {}),
      credentials: 'same-origin',
    });
    let payload = null;
    try {
      payload = await response.json();
    } catch {
      payload = null;
    }
    if (!response.ok) {
      throw new Error((payload && payload.message) || ('HTTP ' + response.status));
    }
    return payload;
  }

  /** 页面内自绘确认框。返回 Promise<boolean>，不依赖 window.confirm。 */
  function dshmAsk(title, message, okLabel) {
    return new Promise((resolve) => {
      const overlay = document.createElement('div');
      overlay.setAttribute('data-dshm-modal', '1');
      overlay.style.cssText = [
        'position:fixed', 'inset:0', 'z-index:2147483000',
        'background:rgba(0,0,0,.55)', 'display:flex',
        'align-items:center', 'justify-content:center',
        'padding:24px', '-webkit-backdrop-filter:blur(2px)', 'backdrop-filter:blur(2px)',
      ].join(';');

      const card = document.createElement('div');
      card.style.cssText = [
        'max-width:360px', 'width:100%', 'border-radius:16px',
        'background:#1d1d21', 'color:#e8e8ea', 'padding:20px',
        'box-shadow:0 12px 40px rgba(0,0,0,.5)',
        'font:15px/1.5 -apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif',
      ].join(';');

      const heading = document.createElement('div');
      heading.textContent = title;
      heading.style.cssText = 'font-size:17px;font-weight:600;margin-bottom:10px';

      const body = document.createElement('div');
      body.textContent = message;
      body.style.cssText = 'white-space:pre-wrap;color:#a8a8b0;font-size:14px;max-height:45vh;overflow:auto';

      const row = document.createElement('div');
      row.style.cssText = 'display:flex;gap:10px;justify-content:flex-end;margin-top:18px';

      const cancel = document.createElement('button');
      cancel.type = 'button';
      cancel.textContent = '取消';
      cancel.style.cssText = 'padding:10px 18px;border-radius:10px;border:1px solid #3a3a42;background:transparent;color:#c8c8d0;font-size:15px';

      const ok = document.createElement('button');
      ok.type = 'button';
      ok.textContent = okLabel || '确定';
      ok.style.cssText = 'padding:10px 18px;border-radius:10px;border:none;background:#d94a4a;color:#fff;font-size:15px;font-weight:600';

      const done = (value) => {
        overlay.remove();
        resolve(value);
      };
      cancel.addEventListener('click', (e) => { e.stopPropagation(); done(false); });
      ok.addEventListener('click', (e) => { e.stopPropagation(); done(true); });
      overlay.addEventListener('click', (e) => { if (e.target === overlay) done(false); });

      row.appendChild(cancel);
      row.appendChild(ok);
      card.appendChild(heading);
      card.appendChild(body);
      card.appendChild(row);
      overlay.appendChild(card);
      document.body.appendChild(overlay);
    });
  }

  function dshmToast(text) {
    const el = document.createElement('div');
    el.setAttribute('data-dshm-toast', '1');
    el.textContent = text;
    el.style.cssText = [
      'position:fixed', 'left:50%', 'bottom:calc(24px + env(safe-area-inset-bottom,0px))',
      'transform:translateX(-50%)', 'z-index:2147483001',
      'max-width:86vw', 'padding:12px 18px', 'border-radius:12px',
      'background:rgba(30,30,34,.96)', 'color:#e8e8ea',
      'font:14px/1.45 -apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif',
      'white-space:pre-wrap', 'box-shadow:0 8px 30px rgba(0,0,0,.45)',
    ].join(';');
    document.body.appendChild(el);
    setTimeout(() => el.remove(), 5200);
  }

  let cascadeBusy = false;

  async function handleCascadeClick(button) {
    if (cascadeBusy) return;
    cascadeBusy = true;
    const sessionId = button.getAttribute(CASCADE_ATTR);
    try {
      const plan = await cascadePost('/plan', { sessionId });
      const nodes = (plan && plan.nodes) || [];
      const children = Math.max(0, nodes.length - 1);
      const live = nodes.filter((node) => node.live === true).length;
      const label = (plan && plan.root && plan.root.title) || sessionId;

      const scope = children > 0
        ? '这会一并删除它的 ' + children + ' 个子会话（共 ' + nodes.length + ' 个），并清除磁盘日志、投影缓存与工作区记录，不可恢复。'
        : '这会清除该会话的磁盘日志、投影缓存与工作区记录，不可恢复。';
      const liveNote = live > 0
        ? '\n\n其中 ' + live + ' 个正在运行：确认后会先停止它们的回合，再执行删除。'
        : '';

      const ok = await dshmAsk(
        '删除会话「' + label + '」？',
        scope + liveNote + '\n\n继续？',
        '删除',
      );
      if (!ok) return;

      const report = await cascadePost('/delete', {
        sessionId,
        dryRun: false,
        includeLive: true,
        allowSelf: true,
        protectSessionId: null,
      });

      const removed = (report && report.removed) || [];
      const skipped = (report && report.skipped) || [];
      const failed = ((report && report.nodes) || []).filter((node) => (node.errors || []).length > 0);

      if (removed.length > 0) {
        const nested = Math.max(0, removed.length - 1);
        const tail = nested > 0 ? '，连同 ' + nested + ' 个子会话' : '';
        const warn = failed.length > 0
          ? '\n' + failed.length + ' 个未能完全清理：' + failed.map((node) => node.id).join(', ')
          : '';
        dshmToast('已删除「' + label + '」' + tail + warn + '\n若它是当前会话，刷新页面后消失');
        return;
      }

      const reasons = skipped.length > 0
        ? skipped.map((item) => item.id + ' — ' + item.reason).join('\n')
        : failed.length > 0
          ? failed.map((node) => node.id + ' — ' + (node.errors || []).join('; ')).join('\n')
          : 'host 未报告任何可删除的产物';
      dshmToast('没有删除任何会话：\n' + reasons);
    } catch (error) {
      dshmToast('删除失败：' + ((error && error.message) || String(error)));
    } finally {
      cascadeBusy = false;
    }
  }

  // 捕获阶段先于 React 的委托处理，拦下插件的 confirm 路径
  document.addEventListener('click', (event) => {
    const node = event.target;
    if (!node || !node.closest) return;
    const button = node.closest('[' + CASCADE_ATTR + ']');
    if (!button) return;
    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();
    void handleCascadeClick(button);
  }, true);

  // ---------------------------------------------------------------- 布局探针
  const describe = (el) => {
    const cls = typeof el.className === 'string' ? el.className.trim().split(/\s+/).slice(0, 3).join('.') : '';
    const id = el.id ? `#${el.id}` : '';
    return `${el.tagName.toLowerCase()}${id}${cls ? '.' + cls : ''}`;
  };

  /** 祖上有 overflow:hidden/auto/scroll 的，说明这块内容是被设计成裁剪的，不算溢出。 */
  const clippedByAncestor = (el) => {
    let p = el.parentElement;
    while (p && p !== document.body) {
      const s = getComputedStyle(p);
      if (s.overflowX === 'hidden' || s.overflowX === 'auto' || s.overflowX === 'scroll') return true;
      p = p.parentElement;
    }
    return false;
  };

  /** 只带结构，不带正文，避免把对话内容回传。 */
  const chainOf = (el, depth = 4) => {
    const out = [];
    let p = el.parentElement;
    for (let i = 0; i < depth && p && p !== document.documentElement; i += 1) {
      const s = getComputedStyle(p);
      const r = p.getBoundingClientRect();
      out.push({
        el: describe(p),
        rectW: Math.round(r.width),
        display: s.display,
        flexWrap: s.flexWrap,
        flexShrink: s.flexShrink,
        overflowX: s.overflowX,
        gap: s.gap,
      });
      p = p.parentElement;
    }
    return out;
  };

  const scanOverflow = () => {
    const vw = window.innerWidth;
    const found = [];
    const clipped = [];
    const nodes = document.querySelectorAll('body *');
    for (const el of nodes) {
      const r = el.getBoundingClientRect();
      if (r.width < 1 || r.height < 1) continue;
      const overRight = r.right - vw;
      const overLeft = -r.left;
      const worst = Math.max(overRight, overLeft);
      if (worst <= 1) continue;
      const style = getComputedStyle(el);
      if (style.visibility === 'hidden' || style.display === 'none' || style.opacity === '0') continue;

      const entry = {
        el: describe(el),
        over: Math.round(worst),
        dir: overRight >= overLeft ? 'right' : 'left',
        rect: { l: Math.round(r.left), t: Math.round(r.top), w: Math.round(r.width), h: Math.round(r.height) },
        position: style.position,
        minWidth: style.minWidth,
        width: style.width,
        flexShrink: style.flexShrink,
        whiteSpace: style.whiteSpace,
      };

      // 左侧越界且整块在屏幕外 = 侧栏收起的正常表现，不算问题
      if (overRight <= 0) {
        clipped.push({ ...entry, why: 'offscreen-left' });
        continue;
      }
      if (clippedByAncestor(el)) {
        clipped.push({ ...entry, why: 'ancestor-clips' });
        continue;
      }
      entry.chain = chainOf(el);
      found.push(entry);
    }
    found.sort((a, b) => b.over - a.over);
    clipped.sort((a, b) => b.over - a.over);
    return {
      viewport: { w: vw, h: window.innerHeight, dpr: window.devicePixelRatio },
      mode: inWebView ? 'webview' : (standalone ? 'standalone' : 'safari'),
      scanned: nodes.length,
      overflowing: found.length,
      suppressed: clipped.length,
      worst: found.slice(0, 12),
      suppressedSample: clipped.slice(0, 8),
    };
  };

  /**
   * 专门量输入区那条工具条，不管它有没有溢出都回报。
   * 插件按钮是运行时注入的（回退/清洗面板/Hook 拦截/数据库/…），
   * 主 CSS 里查不到，只能这样拿真实结构与宽度。
   */
  const probeComposer = () => {
    const bar = document.querySelector('[class*="_trailing"]');
    if (!bar) return { found: false };
    const s = getComputedStyle(bar);
    const r = bar.getBoundingClientRect();
    const kids = Array.from(bar.children).slice(0, 14).map((c) => {
      const cr = c.getBoundingClientRect();
      const cs = getComputedStyle(c);
      return {
        el: describe(c),
        w: Math.round(cr.width),
        h: Math.round(cr.height),
        label: (c.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 12),
        display: cs.display,
        flexShrink: cs.flexShrink,
        marginLeft: cs.marginLeft,
        marginRight: cs.marginRight,
      };
    });
    const parent = bar.parentElement;
    const ps = parent ? getComputedStyle(parent) : null;
    return {
      found: true,
      el: describe(bar),
      rectW: Math.round(r.width),
      scrollW: bar.scrollWidth,
      overflowX: s.overflowX,
      flexWrap: s.flexWrap,
      flexShrink: s.flexShrink,
      gap: s.gap,
      minWidth: s.minWidth,
      parentEl: parent ? describe(parent) : null,
      parentDisplay: ps ? ps.display : null,
      parentFlexWrap: ps ? ps.flexWrap : null,
      parentRectW: parent ? Math.round(parent.getBoundingClientRect().width) : null,
      childCount: bar.children.length,
      children: kids,
      viewportW: window.innerWidth,
    };
  };

  /** 量一下安全区实际值：App 里 env() 应该有非零值，Safari 标签页里是 0。 */  const probeSafeArea = () => {
    const d = document.createElement('div');
    d.style.cssText = 'position:fixed;top:0;left:0;width:0;height:0;visibility:hidden;'
      + 'padding-top:env(safe-area-inset-top);padding-bottom:env(safe-area-inset-bottom);'
      + 'padding-left:env(safe-area-inset-left);padding-right:env(safe-area-inset-right);';
    document.body.appendChild(d);
    const s = getComputedStyle(d);
    const env = {
      top: s.paddingTop, bottom: s.paddingBottom, left: s.paddingLeft, right: s.paddingRight,
    };
    d.remove();
    const rootEl = document.getElementById('root');
    const rs = rootEl ? getComputedStyle(rootEl) : null;
    return {
      env,
      rootHeight: rs ? rs.height : 'n/a',
      rootPaddingBottom: rs ? rs.paddingBottom : 'n/a',
      rootPaddingTop: rs ? rs.paddingTop : 'n/a',
      standaloneFlag: root.dataset.dshmStandalone || 'none',
      webviewFlag: root.dataset.dshmWebview || 'none',
    };
  };

  const report = () => {
    try {
      const data = scanOverflow();
      data.safeArea = probeSafeArea();
      data.composer = probeComposer();
      console.log('[dshm] overflow report', data);
      fetch('/__m/diag', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(data),
        credentials: 'same-origin',
      }).catch(() => {});
    } catch (err) {
      console.log('[dshm] probe failed', err);
    }
  };

  // 等界面挂载完再扫；DSH 首屏是异步渲染的
  let fired = false;
  const schedule = () => {
    if (fired) return;
    fired = true;
    setTimeout(report, 3500);
  };
  if (document.readyState === 'complete') schedule();
  else window.addEventListener('load', schedule, { once: true });

  // 手动触发：控制台里 dshmProbe() 或地址后加 #probe
  window.dshmProbe = report;
  if (location.hash === '#probe') schedule();
})();
