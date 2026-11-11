#!/usr/bin/env node
/**
 * render.mjs — dependency-free HTML/SVG -> PNG/PDF renderer for DSH design work.
 *
 * Drives the locally installed Chromium/Edge over the DevTools protocol (CDP).
 * No npm packages: Node 18+ built-in fetch/WebSocket.
 *
 * Examples
 *   node render.mjs --in poster.html --out poster.png --width 794 --height 1123 --scale 2
 *   node render.mjs --in poster.html --out poster.pdf --pdf --width 210 --height 297 --unit mm
 *   node render.mjs --in logo.svg --out logo.png --selector svg --width 512 --height 512 --transparent
 *   node render.mjs --in long.html --out long.png --full-page --width 1080
 *
 * Exit codes: 0 ok, 2 bad usage, 3 browser not found, 4 render failed.
 */
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { dirname, isAbsolute, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { tmpdir } from 'node:os';
import { createServer } from 'node:net';

// ---------------------------------------------------------------- args
function parseArgs(argv) {
  const o = {
    input: '', out: '', width: 0, height: 0, scale: 1, unit: 'px',
    selector: '', transparent: false, pdf: false, fullPage: false,
    wait: 0, timeout: 30000, dpr: 0, verbose: false, browser: '',
    dpi: 0, audit: false, auditOut: '',
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const next = () => { const v = argv[++i]; if (v === undefined) usage(`missing value for ${a}`); return v; };
    switch (a) {
      case '--in': case '-i': o.input = next(); break;
      case '--out': case '-o': o.out = next(); break;
      case '--width': case '-w': o.width = Number(next()); break;
      case '--height': case '-h': o.height = Number(next()); break;
      case '--scale': case '-s': o.scale = Number(next()); break;
      case '--unit': o.unit = next(); break;
      case '--selector': o.selector = next(); break;
      case '--wait': o.wait = Number(next()); break;
      case '--timeout': o.timeout = Number(next()); break;
      case '--dpi': o.dpi = Number(next()); break;
      case '--audit': o.audit = true; break;
      case '--audit-out': o.audit = true; o.auditOut = next(); break;
      case '--transparent': o.transparent = true; break;
      case '--pdf': o.pdf = true; break;
      case '--full-page': o.fullPage = true; break;
      case '--browser': o.browser = next(); break;
      case '--verbose': o.verbose = true; break;
      case '--help': case '-?': usage(''); break;
      default: usage(`unknown option ${a}`);
    }
  }
  if (!o.input) usage('--in is required');
  if (!o.out) usage('--out is required');
  if (!['px', 'mm', 'in', 'pt'].includes(o.unit)) usage('--unit must be px|mm|in|pt');
  if (o.pdf && o.selector) usage('--selector cannot be combined with --pdf');
  // CSS px per unit (96 dpi CSS reference)
  const px = { px: 1, mm: 96 / 25.4, in: 96, pt: 96 / 72 }[o.unit];
  o.cssWidth = o.width ? o.width * px : 0;
  o.cssHeight = o.height ? o.height * px : 0;
  if (o.fullPage) o.cssHeight = 0;
  if (o.dpi) o.scale = o.dpi / 96; // e.g. --dpi 300 -> 3.125x CSS px
  o.input = isAbsolute(o.input) ? o.input : resolve(o.input);
  o.out = isAbsolute(o.out) ? o.out : resolve(o.out);
  return o;
}
function usage(msg) {
  if (msg) console.error('error: ' + msg);
  console.error('usage: node render.mjs --in <file|url> --out <png|pdf> [--width N --height N --unit px|mm|in|pt] [--scale 2 | --dpi 300] [--selector CSS] [--transparent] [--pdf] [--full-page] [--audit] [--wait ms] [--browser exe]');
  process.exit(msg ? 2 : 0);
}

// ---------------------------------------------------------------- browser discovery
function candidates() {
  const env = process.env;
  const list = [];
  const add = (p) => { if (p) list.push(p); };
  add(env.DSH_BROWSER); add(env.DSH_CHROME); add(env.DSH_EDGE); add(env.CHROME_PATH);
  for (const root of [env['PROGRAMFILES(X86)'], env.PROGRAMFILES, env.LOCALAPPDATA]) {
    if (!root) continue;
    add(join(root, 'Microsoft', 'Edge', 'Application', 'msedge.exe'));
    add(join(root, 'Google', 'Chrome', 'Application', 'chrome.exe'));
    add(join(root, 'Chromium', 'Application', 'chrome.exe'));
  }
  add('C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe');
  add('C:/Program Files/Microsoft/Edge/Application/msedge.exe');
  add('C:/Program Files/Google/Chrome/Application/chrome.exe');
  // playwright cache (any version)
  const pw = join(env.LOCALAPPDATA || '', 'ms-playwright');
  if (existsSync(pw)) {
    try {
      for (const d of readdirSync(pw)) {
        for (const sub of ['chrome-win64/chrome.exe', 'chrome-win/chrome.exe']) {
          add(join(pw, d, ...sub.split('/')));
        }
      }
    } catch { /* ignore */ }
  }
  // POSIX
  for (const p of ['/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge']) add(p);
  return list;
}
function findBrowser(explicit) {
  if (explicit) {
    if (!existsSync(explicit)) throw new Error(`browser not found: ${explicit}`);
    return explicit;
  }
  for (const c of candidates()) { if (existsSync(c)) return c; }
  return '';
}

// ---------------------------------------------------------------- helpers
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function freePort() {
  return await new Promise((res, rej) => {
    const s = createServer();
    s.once('error', rej);
    s.listen(0, '127.0.0.1', () => {
      const p = s.address().port;
      s.close(() => res(p));
    });
  });
}

async function fetchJson(url, tries = 100, delay = 100) {
  let lastErr;
  for (let i = 0; i < tries; i++) {
    try {
      const r = await fetch(url);
      if (r.ok) return await r.json();
      lastErr = new Error(`HTTP ${r.status} ${url}`);
    } catch (e) { lastErr = e; }
    await sleep(delay);
  }
  throw lastErr || new Error(`cannot reach ${url}`);
}

/** Minimal CDP client over the browser websocket. */
class CDP {
  constructor(ws) {
    this.ws = ws;
    this.id = 0;
    this.pending = new Map();
    this.listeners = new Map();
    ws.addEventListener('message', (ev) => {
      const msg = JSON.parse(typeof ev.data === 'string' ? ev.data : Buffer.from(ev.data).toString('utf8'));
      if (msg.id !== undefined) {
        const p = this.pending.get(msg.id);
        if (!p) return;
        this.pending.delete(msg.id);
        if (msg.error) p.reject(new Error(`${p.method}: ${msg.error.message}`));
        else p.resolve(msg.result);
      } else if (msg.method) {
        for (const fn of this.listeners.get(msg.method) || []) fn(msg.params, msg.sessionId);
      }
    });
  }
  on(method, fn) {
    if (!this.listeners.has(method)) this.listeners.set(method, []);
    this.listeners.get(method).push(fn);
    return () => {
      const arr = this.listeners.get(method) || [];
      const i = arr.indexOf(fn);
      if (i >= 0) arr.splice(i, 1);
    };
  }
  send(method, params = {}, sessionId) {
    const id = ++this.id;
    const payload = { id, method, params };
    if (sessionId) payload.sessionId = sessionId;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject, method });
      this.ws.send(JSON.stringify(payload));
    });
  }
}
const onceEvent = (cdp, method, sessionId, timeoutMs) => new Promise((resolve, reject) => {
  const timer = setTimeout(() => { off(); reject(new Error(`timeout waiting for ${method}`)); }, timeoutMs);
  const off = cdp.on(method, (params, sid) => {
    if (sessionId && sid !== sessionId) return;
    clearTimeout(timer); off(); resolve(params);
  });
});

async function connect(url, timeoutMs = 15000) {
  const started = Date.now();
  let lastErr;
  while (Date.now() - started < timeoutMs) {
    try {
      const ws = new WebSocket(url);
      await new Promise((res, rej) => {
        ws.addEventListener('open', res, { once: true });
        ws.addEventListener('error', rej, { once: true });
      });
      return new CDP(ws);
    } catch (e) { lastErr = e; await sleep(120); }
  }
  throw lastErr || new Error('websocket connect failed');
}

function toUrl(input) {
  if (/^(https?|data|file):/i.test(input)) return input;
  return pathToFileURL(input).href;
}

// ---------------------------------------------------------------- main
async function main() {
  const o = parseArgs(process.argv.slice(2));
  const browser = findBrowser(o.browser);
  if (!browser) {
    console.error('error: no Chromium/Edge found. Set DSH_BROWSER=<exe path> or pass --browser.');
    process.exit(3);
  }
  if (!existsSync(o.input) && !/^https?:/i.test(o.input)) {
    console.error(`error: input not found: ${o.input}`);
    process.exit(2);
  }
  mkdirSync(dirname(o.out), { recursive: true });

  const port = await freePort();
  const profile = join(tmpdir(), `dsh-render-${process.pid}-${Date.now()}`);
  const args = [
    '--headless=new', '--disable-gpu', '--hide-scrollbars', '--mute-audio',
    '--no-first-run', '--no-default-browser-check', '--disable-extensions',
    '--disable-background-timer-throttling', '--disable-renderer-backgrounding',
    '--force-color-profile=srgb', '--allow-file-access-from-files',
    `--user-data-dir=${profile}`, `--remote-debugging-port=${port}`, 'about:blank',
  ];
  const proc = spawn(browser, args, { stdio: 'ignore', windowsHide: true });

  let cdp;
  try {
    const version = await fetchJson(`http://127.0.0.1:${port}/json/version`);
    cdp = await connect(version.webSocketDebuggerUrl);

    const { targetId } = await cdp.send('Target.createTarget', { url: 'about:blank' });
    const { sessionId } = await cdp.send('Target.attachToTarget', { targetId, flatten: true });
    const S = sessionId;

    await cdp.send('Page.enable', {}, S);
    await cdp.send('Runtime.enable', {}, S);
    await cdp.send('Emulation.setDeviceMetricsOverride', {
      width: Math.round(o.cssWidth || 1280),
      height: Math.round(o.cssHeight || 800),
      deviceScaleFactor: o.scale,
      mobile: false,
    }, S);
    if (o.transparent) {
      await cdp.send('Emulation.setDefaultBackgroundColorOverride', { color: { r: 0, g: 0, b: 0, a: 0 } }, S);
    }
    // media = screen so @media print rules do not hijack the design
    await cdp.send('Emulation.setEmulatedMedia', { media: 'screen' }, S);

    const loaded = onceEvent(cdp, 'Page.loadEventFired', S, o.timeout);
    await cdp.send('Page.navigate', { url: toUrl(o.input) }, S);
    try { await loaded; } catch (e) {
      // file pages can fire load before we attach; continue and verify readiness below
      if (o.verbose) console.error('note:', e.message);
    }
    // wait for document fonts + images + a settle delay
    const settle = o.wait + 250;
    await cdp.send('Runtime.evaluate', {
      expression: 'document.fonts && document.fonts.ready ? document.fonts.ready.then(()=>true) : true',
      awaitPromise: true, returnByValue: true,
    }, S).catch(() => {});
    await cdp.send('Runtime.evaluate', {
      expression: `Promise.all(Array.from(document.images).filter(i=>!i.complete).map(i=>new Promise(r=>{i.onload=i.onerror=r}))).then(()=>true)`,
      awaitPromise: true, returnByValue: true,
    }, S).catch(() => {});
    if (settle > 0) await sleep(settle);

    if (o.pdf) {
      const r = await cdp.send('Page.printToPDF', {
        printBackground: true,
        preferCSSPageSize: false,
        paperWidth: o.cssWidth ? o.cssWidth / 96 : 8.27,
        paperHeight: o.cssHeight ? o.cssHeight / 96 : 11.69,
        marginTop: 0, marginBottom: 0, marginLeft: 0, marginRight: 0,
        scale: 1,
      }, S).catch(async (e) => {
        if (o.verbose) console.error('note:', e.message);
        return cdp.send('Page.printToPDF', { printBackground: true }, S);
      });
      writeFileSync(o.out, Buffer.from(r.data, 'base64'));
    } else {
      let clip;
      if (o.selector) {
        const { result } = await cdp.send('Runtime.evaluate', {
          expression: `(() => {
            const el = document.querySelector(${JSON.stringify(o.selector)});
            if (!el) return null;
            const r = el.getBoundingClientRect();
            const x = r.left + window.scrollX, y = r.top + window.scrollY;
            return { x, y, width: r.width, height: r.height };
          })()`,
          returnByValue: true,
        }, S);
        if (!result.value) throw new Error(`selector not found or zero-size: ${o.selector}`);
        clip = { ...result.value, scale: 1 };
        if (clip.width < 1 || clip.height < 1) throw new Error(`selector has zero size: ${o.selector}`);
      }
      let height;
      if (o.fullPage) {
        const { result } = await cdp.send('Runtime.evaluate', {
          expression: 'Math.max(document.documentElement.scrollHeight, document.body ? document.body.scrollHeight : 0)',
          returnByValue: true,
        }, S);
        height = Math.ceil(result.value || 800);
        await cdp.send('Emulation.setDeviceMetricsOverride', {
          width: Math.round(o.cssWidth || 1080), height, deviceScaleFactor: o.scale, mobile: false,
        }, S);
        await sleep(120);
      }
      const shot = await cdp.send('Page.captureScreenshot', {
        format: 'png',
        captureBeyondViewport: true,
        fromSurface: true,
        ...(clip ? { clip } : {}),
        ...(height ? {} : {}),
      }, S);
      writeFileSync(o.out, Buffer.from(shot.data, 'base64'));
    }
    const bytes = statSync(o.out).size;
    let audit = null;
    if (o.audit) {
      const { result } = await cdp.send('Runtime.evaluate', {
        expression: `(() => {
          const vw = window.innerWidth;
          const vh = ${o.cssHeight ? Math.round(o.cssHeight) : 'Math.max(document.documentElement.scrollHeight, document.body ? document.body.scrollHeight : 0)'};
          const checkBottom = ${o.fullPage ? 'false' : 'true'};
          const issues = { overflow: [], clipped: [], tiny: [], brokenImages: [], textColors: [] };
          const label = (el) => {
            const cls = typeof el.className === 'string' && el.className.trim()
              ? '.' + el.className.trim().split(/\\s+/).slice(0, 2).join('.') : '';
            const txt = (el.textContent || '').replace(/\\s+/g, ' ').trim().slice(0, 24);
            return el.tagName.toLowerCase() + cls + (txt ? ' "' + txt + '"' : '');
          };
          const colorSeen = new Set();
          const clippedAncestor = (el) => {
            for (let p = el.parentElement; p && p !== document.body; p = p.parentElement) {
              const s = getComputedStyle(p);
              if (s.overflow !== 'visible' || s.overflowX !== 'visible' || s.overflowY !== 'visible') return true;
              if (p.hasAttribute('data-audit-ignore')) return true;
            }
            return false;
          };
          const markedIgnore = (el) => !!el.closest('[data-audit-ignore]');
          for (const el of document.querySelectorAll('body *')) {
            const cs = getComputedStyle(el);
            if (cs.display === 'none' || cs.visibility === 'hidden' || Number(cs.opacity) === 0) continue;
            if (markedIgnore(el)) continue;
            const r = el.getBoundingClientRect();
            if (r.width < 1 || r.height < 1) continue;
            const outL = r.left < -1, outR = r.right > vw + 1, outT = r.top < -1, outB = checkBottom && r.bottom > vh + 1;
            if ((outL || outR || outT || outB) && !clippedAncestor(el)) {
              if (issues.overflow.length < 40) issues.overflow.push({
                el: label(el), left: Math.round(r.left), top: Math.round(r.top),
                right: Math.round(r.right), bottom: Math.round(r.bottom), vw, vh,
                edges: [outL && 'left', outT && 'top', outR && 'right', outB && 'bottom'].filter(Boolean),
              });
            }
            const ownText = el.children.length === 0 && (el.textContent || '').trim().length > 0;
            const clipX = el.scrollWidth > el.clientWidth + 2;
            const clipY = el.scrollHeight > el.clientHeight + 6 && /hidden|clip|auto|scroll/.test(cs.overflowY);
            if (ownText && (clipX || clipY)) {
              if (issues.clipped.length < 40) issues.clipped.push({
                el: label(el), scrollW: el.scrollWidth, clientW: el.clientWidth,
                scrollH: el.scrollHeight, clientH: el.clientHeight,
              });
            }
            if (ownText) {
              const fs = parseFloat(cs.fontSize);
              if (fs && fs < 12 && issues.tiny.length < 40) issues.tiny.push({ el: label(el), fontSize: Math.round(fs * 10) / 10 });
              if (cs.color && !/rgba\\(0, 0, 0, 0\\)/.test(cs.color) && issues.textColors.length < 200) {
                if (!colorSeen.has(cs.color)) { colorSeen.add(cs.color); issues.textColors.push(cs.color); }
              }
            }
          }
          for (const img of document.querySelectorAll('img')) {
            if (!img.complete || img.naturalWidth === 0) issues.brokenImages.push((img.currentSrc || img.src || '').slice(0, 200));
          }
          return {
            viewport: { w: vw, h: vh },
            page: { scrollW: document.documentElement.scrollWidth, scrollH: document.documentElement.scrollHeight },
            pageOverflowX: document.documentElement.scrollWidth > vw + 1,
            fontsStatus: document.fonts ? document.fonts.status : 'n/a',
            fontCount: document.fonts ? document.fonts.size : 0,
            ...issues,
            textColors: issues.textColors.length,
          };
        })()`,
        returnByValue: true, awaitPromise: false,
      }, S).catch(() => ({ result: { value: null } }));
      audit = result.value;
      const errors =
        (audit ? audit.overflow.length + audit.clipped.length + audit.brokenImages.length + (audit.pageOverflowX ? 1 : 0) : 0);
      if (audit) {
        audit.errors = errors;
        audit.warnings = audit.tiny.length + (audit.textColors > 6 ? 1 : 0);
      }
      if (o.auditOut) writeFileSync(o.auditOut, JSON.stringify(audit, null, 2));
    }
    console.log(JSON.stringify({
      ok: true, out: o.out, bytes, browser, mode: o.pdf ? 'pdf' : 'png',
      width: o.cssWidth ? Math.round(o.cssWidth * o.scale) : null,
      height: o.cssHeight ? Math.round(o.cssHeight * o.scale) : null,
      selector: o.selector || null, scale: o.scale,
      ...(audit ? { audit } : {}),
    }));
    if (audit && audit.errors > 0) process.exitCode = 5;
  } catch (e) {
    console.error('render failed: ' + (e && e.message ? e.message : String(e)));
    process.exitCode = 4;
  } finally {
    try { if (cdp) { await cdp.send('Browser.close').catch(() => {}); cdp.ws.close(); } } catch { /* ignore */ }
    try { proc.kill(); } catch { /* ignore */ }
    await sleep(150);
    try { rmSync(profile, { recursive: true, force: true }); } catch { /* ignore */ }
  }
}

main();
