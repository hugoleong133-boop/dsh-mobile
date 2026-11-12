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
