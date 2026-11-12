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
    const cls = typeof el.className === 'string' ? el.className.trim().split(/\s+/).slice(0, 4).join('.') : '';
    const id = el.id ? `#${el.id}` : '';
    const text = (el.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 48);
    return `${el.tagName.toLowerCase()}${id}${cls ? '.' + cls : ''}`;
  };

  const scanOverflow = () => {
    const vw = window.innerWidth;
    const found = [];
    const nodes = document.querySelectorAll('body *');
    for (const el of nodes) {
      if (el.closest('[data-dshm-skip-scan]')) continue;
      const r = el.getBoundingClientRect();
      if (r.width < 1 || r.height < 1) continue;
      const overRight = r.right - vw;
      const overLeft = -r.left;
      const worst = Math.max(overRight, overLeft);
      if (worst <= 1) continue;
      const style = getComputedStyle(el);
      if (style.visibility === 'hidden' || style.display === 'none' || style.opacity === '0') continue;
      found.push({
        el: describe(el),
        over: Math.round(worst),
        dir: overRight >= overLeft ? 'right' : 'left',
        rect: { l: Math.round(r.left), t: Math.round(r.top), w: Math.round(r.width), h: Math.round(r.height) },
        position: style.position,
        minWidth: style.minWidth,
        width: style.width,
        flexShrink: style.flexShrink,
        whiteSpace: style.whiteSpace,
        text: (el.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 60),
      });
    }
    found.sort((a, b) => b.over - a.over);
    return {
      viewport: { w: vw, h: window.innerHeight, dpr: window.devicePixelRatio },
      mode: inWebView ? 'webview' : (standalone ? 'standalone' : 'safari'),
      scanned: nodes.length,
      overflowing: found.length,
      worst: found.slice(0, 25),
    };
  };

  const report = () => {
    try {
      const data = scanOverflow();
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
