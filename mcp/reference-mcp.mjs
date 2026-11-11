#!/usr/bin/env node
/**
 * reference-mcp.mjs — 平面设计工坊 · 参考图联网抓取 MCP 服务
 *
 * 把「联网爬全球参考图」做成一个一等工具（而不是让模型临时想得起去调 PowerShell）：
 *
 *   1. 一等工具（MCP）：reference_search / reference_library / reference_status，
 *      由 preset 直接挂载，工具列表里看得见，不依赖宿主是否注入 web_search。
 *   2. 图片搜索通道：内置 Bing Images（async 端点，imagesize-large 过滤），
 *      直接产出可下载的原图直链；同时保留四个设计站与公共馆藏（由 New-ReferenceBoard.ps1 执行）。
 *   3. 共享参考库 + 缓存：<workspace>/designs/references/.reference-index.json
 *      记录每块板的 signature（检索词+URL+来源），同签名直接命中缓存；
 *      seen 表跨项目去重，已经给过的 URL 不再重复下载。
 *   4. 形态无关：MCP 自己发 HTTP，web/headless 形态下没有宿主 web_search 也能用。
 *
 * 协议：stdio + 换行分隔 JSON-RPC（与 @deepseek-ai/dsh-mcp-client 一致）。零依赖。
 * 日志一律走 stderr，stdout 只写协议消息。
 */

import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import readline from "node:readline";
import process from "node:process";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const BOARD_SCRIPT = path.resolve(HERE, "..", "skills", "graphic-design", "scripts", "New-ReferenceBoard.ps1");

const SERVER = { name: "reference", version: "1.0.0" };
const INDEX_FILE = ".reference-index.json";
const MAX_SEEN = 6000;
const ENGINE_URL_CAP = 18;
const PS_TIMEOUT_MS = 240000;
const UA =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36";

const BUILTIN_SOURCES = ["arena", "designreviewed", "fontsinuse", "itsnicethat", "aic", "met", "cleveland", "commons", "openverse"];
const IMG_RE = /\.(jpe?g|png|webp|gif|bmp|tiff?)(\?[\s\S]*)?$/i;

// 设计站 / 档案 / 策展平台：命中加分（参考要「真设计」，不是商品图和 AI 图）
const DESIGN_HOST_RE =
  /(?:^|\.)(behance\.net|dribbble\.com|are\.na|arena\.na|fontsinuse\.com|designreviewed\.com|itsnicethat\.com|designspiration\.com|siteinspire\.com|typewolf\.com|awwwards\.com|underconsideration\.com|moma\.org|metmuseum\.org|artic\.edu|clevelandart\.org|vam\.ac\.uk|designweek\.co\.uk|dezeen\.com|creativereview\.co\.uk|eyeondesign\.aiga\.org|aiga\.org|zcool\.com\.cn|huaban\.com|xiaohongshu\.com|instagram\.com|tumblr\.com|flickr\.com|fubiz\.net|welovead\.com|adsoftheworld\.com|anothermag\.com|designboom\.com|pinterest\.[a-z.]+|pinimg\.com)$/i;
// 社交 / 灵感流：略加分
const CURATION_HOST_RE = /(?:^|\.)(instagram\.com|tumblr\.com|flickr\.com|pinterest\.[a-z.]+|pinimg\.com|xiaohongshu\.com|huaban\.com)$/i;
// 电商 / 图库 / 模板店 / AI 生图站：直接判负
const JUNK_HOST_RE =
  /(?:^|\.)(etsy\.com|amazon\.[a-z.]+|ebay\.[a-z.]+|walmart\.com|target\.com|wayfair\.[a-z.]+|zazzle\.[a-z.]+|redbubble\.com|society6\.com|fineartamerica\.com|saatchiart\.com|art\.com|posterburner\.com|shutterstock\.com|istockphoto\.com|gettyimages\.[a-z.]+|alamy\.com|dreamstime\.com|depositphotos\.com|123rf\.com|vectorstock\.com|freepik\.com|canva\.com|stock\.adobe\.com|envato\.com|creativemarket\.com|templatemonster\.com|midjourney\.com|openart\.ai|leonardo\.ai|civitai\.com|nightcafe\.studio|stablediffusionweb\.com|mew\.design|lexica\.art|prompthero\.com|tensor\.art|vondy\.com|playground\.com|ideogram\.ai|krea\.ai|renderforest\.com)$/i;
// 商品文案 / AI 图 / 模板 / 水印 / 印刷品货架：同样判负
const JUNK_TEXT_RE =
  /(ai[\s-]?generated|midjourney|stable diffusion|dall[\s-]?e|generative ai|ai art|printable|instant download|digital download|wall art|canvas print|art print|gicl[eé]e|museum-quality|limited edition|unframed|framed print|metal print|for sale|buy now|add to cart|free shipping|wall decor|t-shirt|hoodie|sticker pack|template|mockup|watermark|\b\d{3,4}x\d{3,4}\b)/i;
// 电商/印刷品店铺的域名与路径（"poster"/"print"/"shop"/"cart" 这类词几乎只出现在卖画的站）
const SHOP_HOST_RE = /(?:^|\.)[a-z0-9-]*(shop|store|prints?|posters?|canvas|wallart|artprint|posterarchive|decor)[a-z0-9-]*\.[a-z.]+$/i;
const SHOP_PATH_RE = /\/(shop|store|products?|cart|checkout|collections?)\//i;

// ───────────────────────────────── 小工具 ─────────────────────────────────

const log = (...args) => process.stderr.write(`[reference-mcp] ${args.join(" ")}\n`);

const sha1 = (s) => createHash("sha1").update(s).digest("hex");
const clamp = (n, lo, hi, dflt) => {
  const v = Number(n);
  if (!Number.isFinite(v)) return dflt;
  return Math.min(hi, Math.max(lo, Math.round(v)));
};

function slugify(input) {
  const base = String(input || "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9\-\s]/g, " ")
    .replace(/\s+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
  return base.slice(0, 48);
}

function normalizeUrl(raw) {
  let u = String(raw || "").trim();
  if (!u) return "";
  u = u.replace(/[\r\n\t]/g, "");
  try {
    const parsed = new URL(u);
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") return "";
    parsed.hash = "";
    return parsed.toString();
  } catch {
    return "";
  }
}

function hostOf(raw) {
  try {
    return new URL(raw).hostname.toLowerCase();
  } catch {
    return "";
  }
}

/**
 * Bing 的标题常带站点后缀（"… :: Behance"、"… | Images"），清掉再当参考板标签。
 */
function cleanTitle(raw, host) {
  let t = String(raw || "").replace(/\s+/g, " ").trim();
  t = t.replace(/\s*(?:::|\||-|—|–)\s*(Behance|Dribbble|Are\.na|Pinterest|Instagram|ArtStation|ZCOOL|站酷)\s*$/i, "");
  t = t.replace(/\s+(on|@)\s*(Behance|Dribbble|Are\.na|Pinterest|Instagram)\s*$/i, "");
  t = t.replace(/\s*\|\s*Images?\s*$/i, "");
  if (!t) t = host || "";
  return t.slice(0, 120);
}

/**
 * 给 Bing 候选打分：设计站/档案 +3，灵感流 +1，电商/图库/AI 站或商品文案 -10。
 * 只收 score >= 0 的候选——参考宁可少，不要一板子商品图和 AI 图。
 */
function scoreCandidate(item) {
  const murl = normalizeUrl(item.murl);
  if (!murl || !IMG_RE.test(murl)) return null;
  if (/tse\d*\.mm\.bing\.net|th\.bing\.com|mm\.bing\.net/i.test(murl)) return null;
  const purl = normalizeUrl(item.purl);
  const pHost = hostOf(purl);
  const mHost = hostOf(murl);
  const title = String(item.t || "").slice(0, 200);
  const hay = `${title} ${purl} ${murl}`.toLowerCase();

  let score = 0;
  let reason = "";
  if (DESIGN_HOST_RE.test(pHost)) score += 3;
  else if (CURATION_HOST_RE.test(pHost)) score += 1;
  else if (pHost) {
    // 来源不限，但参考板优先收「真的在做设计」的站：博客/新闻/电商的配图噪声太大，
    // 想让某个页面进板子，用 url 参数显式喂进来（这条路不受这条打分限制）。
    score -= 1;
    reason = "off-domain";
  }

  let shop = false;
  if (SHOP_HOST_RE.test(pHost) || SHOP_HOST_RE.test(mHost)) {
    shop = true;
    reason = "shop-host";
  } else if (purl && SHOP_PATH_RE.test(new URL(purl).pathname)) {
    shop = true;
    reason = "shop-path";
  }

  if (shop || JUNK_HOST_RE.test(pHost) || JUNK_HOST_RE.test(mHost)) {
    if (!reason) reason = "junk-host";
    score -= 10;
  } else if (JUNK_TEXT_RE.test(hay)) {
    score -= 10;
    reason = "junk-text";
  }
  return { score, reason, url: murl, pageUrl: purl, title, pageHost: pHost };
}

function decodeEntities(s) {
  return String(s)
    .replace(/&quot;/g, '"')
    .replace(/&#34;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&#x27;/gi, "'")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&#x2F;/gi, "/")
    .replace(/&#(\d+);/g, (_, d) => String.fromCharCode(Number(d)));
}

const psQuote = (s) => "'" + String(s).replace(/'/g, "''") + "'";

const joinQueries = (queries) =>
  queries.map((q) => String(q).replace(/[;|\r\n]+/g, " ").trim()).filter(Boolean).join(";");

const joinUrls = (urls) =>
  urls
    .map((u) => String(u).replace(/[\r\n]/g, "").replace(/;/g, "%3B").replace(/\|/g, "%7C").replace(/ /g, "%20"))
    .join(";");

// ───────────────────────────────── 工作区 ─────────────────────────────────

function looksBlocked(p) {
  const low = p.toLowerCase();
  return /[\\/]programs[\\/]/.test(low) || /[\\/]appdata[\\/]local[\\/]programs/.test(low) || /\.asar/.test(low);
}

/**
 * 解析工作区：显式参数 > 环境变量 > 进程 cwd。
 * 进程 cwd 若是安装目录（Program Files 等）则拒绝——避免把 designs/ 写进程序目录。
 */
function resolveWorkspace(arg) {
  if (arg && String(arg).trim()) {
    return { workspace: path.resolve(String(arg).trim()), source: "argument" };
  }
  for (const key of ["DSH_WORKING_DIR", "DSH_SESSION_CWD", "DSH_CWD"]) {
    if (process.env[key] && process.env[key].trim()) {
      return { workspace: path.resolve(process.env[key].trim()), source: `env:${key}` };
    }
  }
  const cwd = process.cwd();
  if (!looksBlocked(cwd)) return { workspace: cwd, source: "cwd" };
  return {
    workspace: "",
    source: "unresolved",
    error:
      "无法确定工作区：进程 cwd 是程序安装目录（" +
      cwd +
      "）。请显式传 workspace=<你的会话工作目录绝对路径>（就是包含 designs/ 的那个目录）。",
  };
}

const refsRoot = (ws) => path.join(ws, "designs", "references");
const indexPath = (ws) => path.join(refsRoot(ws), INDEX_FILE);

function readIndex(ws) {
  const empty = { version: 1, updatedAt: "", boards: {}, seen: {} };
  try {
    const raw = fs.readFileSync(indexPath(ws), "utf8").replace(/^\uFEFF/, "");
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object") return empty;
    return {
      version: 1,
      updatedAt: parsed.updatedAt || "",
      boards: parsed.boards && typeof parsed.boards === "object" ? parsed.boards : {},
      seen: parsed.seen && typeof parsed.seen === "object" ? parsed.seen : {},
    };
  } catch {
    return empty;
  }
}

function writeIndex(ws, index) {
  const file = indexPath(ws);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const seenKeys = Object.keys(index.seen);
  if (seenKeys.length > MAX_SEEN) {
    seenKeys
      .sort((a, b) => String(index.seen[a]?.at || "").localeCompare(String(index.seen[b]?.at || "")))
      .slice(0, seenKeys.length - MAX_SEEN)
      .forEach((k) => delete index.seen[k]);
  }
  index.updatedAt = new Date().toISOString();
  const tmp = file + ".tmp";
  fs.writeFileSync(tmp, JSON.stringify(index, null, 2), "utf8");
  fs.renameSync(tmp, file);
}

function readBoard(ws, slug) {
  const dir = path.join(refsRoot(ws), slug);
  const refsPath = path.join(dir, "refs.json");
  if (!fs.existsSync(refsPath)) return null;
  try {
    const manifest = JSON.parse(fs.readFileSync(refsPath, "utf8").replace(/^\uFEFF/, ""));
    return { dir, refsPath, manifest };
  } catch {
    return null;
  }
}

const signatureOf = ({ queries, urls, sources, engine }) =>
  sha1(
    JSON.stringify({
      q: [...(queries || [])].map((q) => q.toLowerCase()).sort(),
      u: [...(urls || [])].map((u) => u.toLowerCase()).sort(),
      s: [...(sources || [])].sort(),
      e: engine || "bing",
    }),
  );

// ───────────────────────────────── 网络 ─────────────────────────────────

async function fetchText(url, { timeoutMs = 20000, headers = {}, method = "GET" } = {}) {
  const res = await fetch(url, {
    method,
    redirect: "follow",
    signal: AbortSignal.timeout(timeoutMs),
    headers: {
      "User-Agent": UA,
      Accept: "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
      "Accept-Language": "en-US,en;q=0.9,zh-CN;q=0.8",
      ...headers,
    },
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`HTTP ${res.status} ${res.statusText} — ${url}`);
  return text;
}

/** 从 Bing Images 的 async HTML 里抽原图直链。 */
function parseBingHtml(html) {
  const out = [];
  const patterns = [/m="(\{&quot;[\s\S]*?\})"/g, /m='(\{&quot;[\s\S]*?\})'/g, /m="(\{"murl"[\s\S]*?\})"/g];
  for (const re of patterns) {
    let m;
    while ((m = re.exec(html))) {
      try {
        const item = JSON.parse(decodeEntities(m[1]));
        if (item && item.murl) out.push(item);
      } catch {
        /* 单条解析失败不影响其他条目 */
      }
    }
    if (out.length) break;
  }
  return out;
}

async function searchBing(query, pages = 1) {
  const items = [];
  for (let page = 0; page < pages; page++) {
    const first = page * 35 + 1;
    const url =
      "https://www.bing.com/images/async?q=" +
      encodeURIComponent(query) +
      `&first=${first}&count=35&mmasync=1&qft=+filterui:imagesize-large`;
    try {
      const html = await fetchText(url, { timeoutMs: 20000 });
      items.push(...parseBingHtml(html));
    } catch (err) {
      log(`bing page ${page + 1} failed for "${query}": ${err.message}`);
      break;
    }
  }
  return items;
}

async function probe(url, timeoutMs = 12000, headers = {}, attempts = 2) {
  const started = Date.now();
  let last = { ok: false, status: 0, ms: 0 };
  for (let i = 0; i < attempts; i++) {
    try {
      const res = await fetch(url, {
        method: "GET",
        signal: AbortSignal.timeout(timeoutMs),
        headers: { "User-Agent": UA, Accept: "*/*", ...headers },
      });
      const ms = Date.now() - started;
      if (res.status === 403 || res.status === 429) return { ok: false, blocked: true, status: res.status, ms };
      if (res.ok) return { ok: true, status: res.status, ms };
      last = { ok: false, status: res.status, ms };
      if (res.status < 500) return last;
    } catch (err) {
      last = { ok: false, status: 0, ms: Date.now() - started, error: err.message };
    }
    await new Promise((r) => setTimeout(r, 400));
  }
  return last;
}

// ─────────────────────────────── PowerShell ───────────────────────────────

function buildPsCommand({ workspace, slug, queries, urls, sources, limit, max, minWidth, clean, urlMeta }) {
  const lines = [
    "$ErrorActionPreference='Stop'",
    "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8",
    "$ProgressPreference='SilentlyContinue'",
  ];
  const args = [`-Workspace ${psQuote(workspace)}`, `-Slug ${psQuote(slug)}`];
  if (queries.length) args.push(`-Query ${psQuote(joinQueries(queries))}`);
  if (urls.length) args.push(`-Url ${psQuote(joinUrls(urls))}`);
  if (urlMeta) args.push(`-UrlMeta ${psQuote(urlMeta)}`);
  if (sources.length) args.push(`-Sources ${psQuote(sources.join("|"))}`);
  args.push(`-Limit ${limit}`, `-Max ${max}`, `-MinWidth ${minWidth}`);
  if (clean) args.push("-Clean");
  lines.push(`& ${psQuote(BOARD_SCRIPT)} ${args.join(" ")}`);
  return lines.join("\n");
}

function runPowershell(command, timeoutMs = PS_TIMEOUT_MS) {
  return new Promise((resolve) => {
    const encoded = Buffer.from(command, "utf16le").toString("base64");
    const child = spawn(
      "powershell.exe",
      ["-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", encoded],
      { windowsHide: true, env: process.env },
    );
    let stdout = "";
    let stderr = "";
    let timedOut = false;
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (d) => {
      stdout += d;
      if (stdout.length > 4_000_000) stdout = stdout.slice(-4_000_000);
    });
    child.stderr.on("data", (d) => {
      stderr += d;
      if (stderr.length > 200_000) stderr = stderr.slice(-200_000);
    });
    const timer = setTimeout(() => {
      timedOut = true;
      try {
        child.kill();
      } catch {
        /* ignore */
      }
    }, timeoutMs);
    child.on("error", (err) => {
      clearTimeout(timer);
      resolve({ code: -1, stdout, stderr: stderr + "\n" + err.message, timedOut });
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      resolve({ code, stdout, stderr, timedOut });
    });
  });
}

/** PowerShell 脚本最后会打印一个 JSON 汇总；前面可能混着别的输出，取最后一个完整对象。 */
function extractJson(text) {
  const trimmed = String(text || "").trim();
  if (!trimmed) return null;
  try {
    return JSON.parse(trimmed.slice(trimmed.lastIndexOf("\n{") + 1));
  } catch {
    /* fall through */
  }
  for (let i = trimmed.lastIndexOf("{"); i >= 0; i = trimmed.lastIndexOf("{", i - 1)) {
    try {
      return JSON.parse(trimmed.slice(i));
    } catch {
      if (i === 0) break;
    }
  }
  return null;
}

// ───────────────────────────────── 工具实现 ─────────────────────────────────

function boardSummary(board, slug) {
  const m = board.manifest;
  const bySource = {};
  for (const item of m.items || []) bySource[item.source] = (bySource[item.source] || 0) + 1;
  return {
    slug,
    dir: board.dir,
    workspaceNote: "参考图只进判断、不进画布",
    count: m.count || (m.items || []).length,
    designCount: m.designCount || 0,
    museumCount: m.museumCount || 0,
    bySource,
    qualityGate: m.qualityGate,
    board: path.join(board.dir, "board.png"),
    manifest: board.refsPath,
    readme: path.join(board.dir, "REFS.md"),
    createdAt: m.createdAt,
    items: (m.items || []).slice(0, 24).map((it) => ({
      index: it.index,
      title: it.title,
      creator: it.creator,
      date: it.date,
      source: it.source,
      width: it.width,
      height: it.height,
      pageUrl: it.pageUrl,
    })),
  };
}

async function toolSearch(args) {
  const startedAt = Date.now();
  const resolved = resolveWorkspace(args.workspace);
  if (!resolved.workspace) {
    return { ok: false, error: "workspace_required", message: resolved.error };
  }
  const ws = resolved.workspace;

  const queries = (Array.isArray(args.query) ? args.query : args.query ? [args.query] : [])
    .map((q) => String(q || "").trim())
    .filter(Boolean)
    .slice(0, 6);
  const urls = (Array.isArray(args.url) ? args.url : args.url ? [args.url] : [])
    .map((u) => normalizeUrl(u))
    .filter(Boolean)
    .slice(0, 24);

  if (!queries.length && !urls.length) {
    return {
      ok: false,
      error: "query_required",
      message:
        "至少给一组检索词（query）或一个页面/图片直链（url）。检索词用 movement + medium + decade，例如 \"swiss style poster 1960s\"。",
    };
  }

  const engine = args.engine === "none" ? "none" : "bing";
  const enginePages = clamp(args.enginePages, 1, 3, 1);
  const sources = (Array.isArray(args.sources) && args.sources.length ? args.sources : ["arena", "designreviewed"])
    .map((s) => String(s).trim().toLowerCase())
    .filter((s) => BUILTIN_SOURCES.includes(s));
  const limit = clamp(args.limit, 1, 8, 3);
  const max = clamp(args.max, 4, 24, 12);
  const minWidth = clamp(args.minWidth, 600, 4000, 1200);
  const refresh = Boolean(args.refresh);

  if (!fs.existsSync(BOARD_SCRIPT)) {
    return { ok: false, error: "script_missing", message: `找不到抓取脚本：${BOARD_SCRIPT}` };
  }

  const signature = signatureOf({ queries, urls, sources, engine });
  const index = readIndex(ws);

  // ① 缓存命中：同签名、够张数、未要求刷新 → 直接返回已有参考板
  if (!refresh) {
    for (const [slug, entry] of Object.entries(index.boards)) {
      if (entry.signature !== signature) continue;
      const board = readBoard(ws, slug);
      if (!board) continue;
      const count = board.manifest.count || (board.manifest.items || []).length;
      if (count < Math.min(4, max)) continue;
      return {
        ok: true,
        cached: true,
        workspace: ws,
        workspaceSource: resolved.source,
        note: "命中共享参考库（同检索词/同来源）。要重新联网抓，传 refresh:true；要复用别的板子，用 reference_library。",
        ...boardSummary(board, slug),
      };
    }
  }

  // ② 图片搜索通道（Bing）：拿到原图直链，交给参考板脚本统一下载/质检/拼版
  const engineInfo = {
    provider: engine,
    queries: [],
    found: 0,
    offered: 0,
    rejected: 0,
    rejectedBy: {},
    skippedSeen: 0,
    topHosts: [],
  };
  const engineUrls = [];
  if (engine === "bing" && queries.length) {
    const perQuery = [];
    for (const q of queries.slice(0, 3)) {
      const found = await searchBing(q, enginePages);
      engineInfo.found += found.length;
      engineInfo.queries.push({ query: q, found: found.length });
      perQuery.push(found);
    }

    // 轮询各检索词的结果，避免第一个词吃掉全部名额；先打分再收，商品图/AI 图直接扔
    const pool = [];
    const poolSeen = new Set();
    let added = true;
    let guard = 0;
    while (added && guard++ < 60) {
      added = false;
      for (const list of perQuery) {
        const next = list.shift();
        if (!next) continue;
        added = true;
        const cand = scoreCandidate(next);
        if (!cand) {
          engineInfo.rejected++;
          engineInfo.rejectedBy.format = (engineInfo.rejectedBy.format || 0) + 1;
          continue;
        }
        if (cand.score < 0) {
          engineInfo.rejected++;
          const key = cand.reason || "other";
          engineInfo.rejectedBy[key] = (engineInfo.rejectedBy[key] || 0) + 1;
          continue;
        }
        if (poolSeen.has(cand.url)) continue;
        poolSeen.add(cand.url);
        pool.push(cand);
      }
    }

    pool.sort((a, b) => b.score - a.score);
    const picked = [];
    for (const cand of pool) {
      if (picked.length >= ENGINE_URL_CAP) break;
      if (index.seen[cand.url] && !refresh) {
        engineInfo.skippedSeen++;
        continue;
      }
      picked.push(cand);
    }
    engineInfo.offered = picked.length;
    engineInfo.topHosts = [...new Set(picked.map((p) => p.pageHost).filter(Boolean))].slice(0, 6);
    for (const p of picked) engineUrls.push(p.url);
    engineInfo.details = picked;
  }

  const allUrls = [...urls, ...engineUrls];
  const engineMs = Date.now() - startedAt;

  // ③ 选 slug：同签名复用已有目录（refresh 时覆盖），否则取用户指定 / 首个检索词派生，撞名加序号
  let slug = slugify(args.slug) || slugify(queries[0]) || `ref-${signature.slice(0, 6)}`;
  let clean = false;
  const taken = (name) => Boolean(readBoard(ws, name));
  const sameQuerySet = (board) =>
    JSON.stringify((board.manifest.queries || []).map((q) => String(q).trim().toLowerCase()).sort()) ===
    JSON.stringify(queries.map((q) => q.toLowerCase()).sort());
  if (taken(slug)) {
    const existing = readBoard(ws, slug);
    if (refresh && existing && sameQuerySet(existing)) {
      clean = true; // 显式刷新：沿用同一块板，先清掉旧图
    } else {
      let n = 2;
      while (taken(`${slug}-${n}`)) n++;
      slug = `${slug}-${n}`;
    }
  }

  // ④ 跑参考板脚本（下载 / 质量门槛 / 去重 / 拼版）
  //    搜索引擎拿到的直链没有标题与出处，写一份 UrlMeta 给脚本补上（标签和 REFS.md 才有溯源）
  let metaFile = "";
  const details = engineInfo.details || [];
  if (details.length) {
    const rows = details.map((c) => {
      const host = (c.pageHost || "").replace(/^www\./, "");
      return {
        imageUrl: c.url,
        title: cleanTitle(c.title, host),
        pageUrl: c.pageUrl || "",
        source: host ? `Web · ${host}` : "Direct image",
      };
    });
    try {
      metaFile = path.join(os.tmpdir(), `dsh-refmeta-${process.pid}-${signature.slice(0, 8)}.json`);
      fs.writeFileSync(metaFile, JSON.stringify(rows), "utf8");
    } catch {
      metaFile = "";
    }
  }

  const command = buildPsCommand({
    workspace: ws,
    slug,
    queries,
    urls: allUrls,
    sources,
    limit,
    max,
    minWidth,
    clean,
    urlMeta: metaFile,
  });
  const run = await runPowershell(command);
  if (metaFile) {
    try {
      fs.unlinkSync(metaFile);
    } catch {
      /* ignore */
    }
  }
  const timing = { engineMs, boardScriptMs: Date.now() - startedAt - engineMs, totalMs: Date.now() - startedAt };

  if (run.timedOut) {
    return {
      ok: false,
      error: "timeout",
      message: `抓取超过 ${Math.round(PS_TIMEOUT_MS / 1000)}s 未完成。把 max 调小（如 8）、少给几个检索词后重试。`,
      slug,
      stderr: run.stderr.slice(-1200),
    };
  }

  const summary = extractJson(run.stdout);
  if (!summary || summary.ok !== true) {
    return {
      ok: false,
      error: "crawl_failed",
      message:
        (summary && summary.message) ||
        "参考板脚本没有返回可用的 JSON。可能是检索没有命中、全部低于质量门槛，或网络不通。",
      slug,
      stderr: run.stderr.slice(-1600),
      stdout: run.stdout.slice(-800),
      hints: [
        "换更具体的词（movement + medium + decade），或先用 web_search 找页面再放到 url 里",
        "给 minWidth 降到 1000 可以放宽门槛",
        "reference_status 可以检查各来源连通性",
      ],
    };
  }

  const board = readBoard(ws, slug);
  const items = (board?.manifest.items || []).map((it) => ({
    index: it.index,
    title: it.title,
    creator: it.creator,
    date: it.date,
    source: it.source,
    width: it.width,
    height: it.height,
    pageUrl: it.pageUrl,
    imageUrl: it.imageUrl,
  }));

  // ⑤ 写回共享库索引（签名 + 来源 + seen）
  const now = new Date().toISOString();
  index.boards[slug] = {
    slug,
    dir: board?.dir || path.join(refsRoot(ws), slug),
    signature,
    queries,
    urls,
    sources,
    engine,
    count: summary.count,
    designCount: summary.designCount,
    museumCount: summary.museumCount,
    bySource: summary.bySource || {},
    createdAt: summary.createdAt || now,
    updatedAt: now,
  };
  const used = new Set(items.map((i) => normalizeUrl(i.imageUrl)).filter(Boolean));
  for (const it of items) {
    const u = normalizeUrl(it.imageUrl);
    if (u) index.seen[u] = { slug, status: "used", at: now };
  }
  for (const e of engineInfo.details || []) {
    if (!used.has(e.url)) index.seen[e.url] = { slug, status: "offered", at: now };
  }
  for (const u of urls) index.seen[u] = { slug, status: "used", at: now };
  writeIndex(ws, index);

  // ⑥ 引擎溯源落盘，方便复查「这张图是从哪搜到的」
  try {
    fs.writeFileSync(
      path.join(summary.dir, "engine.json"),
      JSON.stringify(
        {
          provider: engineInfo.provider,
          queries,
          pages: enginePages,
          offered: engineInfo.offered,
          skippedSeen: engineInfo.skippedSeen,
          candidates: engineInfo.details || [],
          generatedAt: now,
        },
        null,
        2,
      ),
      "utf8",
    );
  } catch {
    /* 溯源文件失败不影响主流程 */
  }

  const warnings = (summary.warnings || []).slice(0, 12);
  return {
    ok: true,
    cached: false,
    workspace: ws,
    workspaceSource: resolved.source,
    slug,
    dir: summary.dir,
    count: summary.count,
    designCount: summary.designCount,
    museumCount: summary.museumCount,
    bySource: summary.bySource,
    qualityGate: summary.qualityGate,
    board: summary.board,
    manifest: summary.manifest,
    readme: summary.readme,
    items: items.slice(0, 24),
    engine: {
      provider: engineInfo.provider,
      queries: engineInfo.queries,
      found: engineInfo.found,
      offered: engineInfo.offered,
      skippedSeen: engineInfo.skippedSeen,
      deduped: engineInfo.skippedSeen,
      rejected: engineInfo.rejected,
      rejectedBy: engineInfo.rejectedBy,
      pageHosts: engineInfo.topHosts,
      note:
        engineInfo.offered === 0 && engineInfo.rejected > 0
          ? "图片搜索引擎这次没给出可用结果（命中的都是商品/图库/AI 图，已剔除）；本板来自内置设计站与馆藏。换更具体的词，或用 url 直接喂你找到的页面。"
          : "",
    },
    library: { boards: Object.keys(index.boards).length, seenUrls: Object.keys(index.seen).length },
    timing,
    warnings,
    next: [
      "read_image 看 board.png，再逐张看 img/0X（标题区/信息区放大看）",
      `写 designs/${slug}/reference-study.md（7 条，不许编数字）`,
      `把编号参考板 + 精读摘要 + 三问发给用户过审，原话记进 designs/${slug}/refs-approved.md`,
      "过审之前不许写设计决策单、不许开画布",
    ],
  };
}

function toolLibrary(args) {
  const resolved = resolveWorkspace(args.workspace);
  if (!resolved.workspace) return { ok: false, error: "workspace_required", message: resolved.error };
  const ws = resolved.workspace;
  const index = readIndex(ws);
  const needle = String(args.query || "").trim().toLowerCase();
  const limit = clamp(args.limit, 1, 100, 20);

  // 索引 + 目录扫描：老项目里已有的板子（本 MCP 之前抓的）也要能被复用
  const known = new Map();
  for (const [slug, b] of Object.entries(index.boards)) known.set(slug, { ...b, indexed: true });
  let dirs = [];
  try {
    dirs = fs
      .readdirSync(refsRoot(ws), { withFileTypes: true })
      .filter((d) => d.isDirectory())
      .map((d) => d.name);
  } catch {
    /* 目录还不存在 */
  }
  for (const slug of dirs) {
    if (known.has(slug)) continue;
    const board = readBoard(ws, slug);
    if (!board) continue;
    const m = board.manifest;
    known.set(slug, {
      slug,
      dir: board.dir,
      indexed: false,
      queries: m.queries || [],
      sources: m.sources || [],
      engine: "unknown",
      createdAt: m.createdAt,
      updatedAt: m.createdAt,
      count: m.count || (m.items || []).length,
    });
  }

  const boards = [...known.values()]
    .filter((b) => {
      if (!needle) return true;
      const hay = [b.slug, ...(b.queries || []), ...(b.sources || [])].join(" ").toLowerCase();
      return hay.includes(needle);
    })
    .sort((a, b) => String(b.updatedAt || b.createdAt || "").localeCompare(String(a.updatedAt || a.createdAt || "")))
    .slice(0, limit)
    .map((b) => {
      const board = readBoard(ws, b.slug);
      const count = board ? board.manifest.count || (board.manifest.items || []).length : b.count;
      return {
        slug: b.slug,
        count,
        queries: b.queries || [],
        sources: b.sources || [],
        engine: b.engine,
        indexed: Boolean(b.indexed),
        createdAt: b.createdAt,
        updatedAt: b.updatedAt,
        board: board ? path.join(board.dir, "board.png") : "",
        dir: board ? board.dir : b.dir || "",
        exists: Boolean(board),
      };
    });

  return {
    ok: true,
    workspace: ws,
    workspaceSource: resolved.source,
    total: known.size,
    matched: boards.length,
    images: boards.reduce((sum, b) => sum + (Number(b.count) || 0), 0),
    boards,
    note: boards.length
      ? "复用旧板子前必须先 read_image 重新看一遍，不要凭记忆。要整块板子重抓就 reference_search 传同一 slug + refresh:true。"
      : "共享库里还没有匹配的参考板；先 reference_search 抓一块。",
  };
}

async function toolStatus(args) {
  const resolved = resolveWorkspace(args.workspace);
  const ws = resolved.workspace;
  const checks = await Promise.all([
    probe("https://www.bing.com/images/async?q=swiss%20poster&first=1&count=5&mmasync=1", 12000),
    probe("https://api.are.na/v2/search?q=bauhaus&type=Image&per=1", 12000),
    probe("https://designreviewed.com/wp-json/wp/v2/posts?search=poster&per_page=1", 12000),
    probe("https://fontsinuse.com/search?q=swiss", 12000),
    probe("https://www.itsnicethat.com/articles?search=design", 12000),
  ]);
  const names = ["bing", "arena", "designreviewed", "fontsinuse", "itsnicethat"];
  const sources = Object.fromEntries(names.map((n, i) => [n, checks[i]]));
  const index = ws ? readIndex(ws) : { boards: {}, seen: {} };

  return {
    ok: true,
    workspace: ws || "",
    workspaceSource: resolved.source,
    workspaceError: resolved.error,
    cwd: process.cwd(),
    process: { node: process.version, platform: process.platform },
    script: { path: BOARD_SCRIPT, exists: fs.existsSync(BOARD_SCRIPT) },
    sources,
    library: { boards: Object.keys(index.boards).length, seenUrls: Object.keys(index.seen).length },
    hints: Object.entries(sources)
      .filter(([, v]) => !v.ok)
      .map(([k, v]) =>
        v.blocked
          ? `${k} 拒爬（HTTP ${v.status}）：这一路本次抓不到，靠 bing 图片搜索、-Url 或换来源`
          : `${k} 不通：换来源或先用 web_search 找页面再放进 url`,
      ),
  };
}

// ───────────────────────────────── 工具定义 ─────────────────────────────────

const TOOLS = [
  {
    name: "reference_search",
    description:
      "联网抓全球参考图并生成编号参考板（设计风格研究用）。一次调用完成：Bing 图片搜索（原图直链，自动剔除电商/图库/AI 生图/模板站，设计站与档案加分）+ 四个设计站（Are.na / Design Reviewed / Fonts In Use / It's Nice That）+ 任意页面或图片直链 + 可选公共馆藏 → 下载 → 质量门槛（宽≥minWidth、>20KB、能解码）→ 去重 → 拼 board.png → 写 refs.json/REFS.md → 记入共享参考库。同检索词/来源的板子会命中缓存（传 refresh:true 重新联网抓）。参考图只做研究，绝不置入成品。",
    inputSchema: {
      type: "object",
      properties: {
        query: {
          type: "array",
          items: { type: "string" },
          description:
            "检索词，英文效果最好：movement + medium + decade，如 [\"swiss style poster 1960s\",\"soviet constructivist poster\"]。中英文各搜一遍。",
        },
        url: {
          type: "array",
          items: { type: "string" },
          description: "额外页面或图片直链（web_search 命中的 Behance/站酷/Pinterest/品牌站/档案馆页面都行）。",
        },
        sources: {
          type: "array",
          items: { type: "string", enum: BUILTIN_SOURCES },
          description: "内置来源子集，默认 [\"arena\",\"designreviewed\"]；馆藏（aic/met/cleveland/commons/openverse）关键词检索偏松，需逐张核年代与媒介。",
        },
        engine: { type: "string", enum: ["bing", "none"], description: "图片搜索引擎，默认 bing；离线或不想走搜索引擎时用 none（只走 URL/内置站）。" },
        enginePages: { type: "integer", minimum: 1, maximum: 3, description: "每个检索词翻几页 Bing（每页 35 条），默认 1。" },
        slug: { type: "string", description: "参考板目录名（英文/数字/短横线）；缺省从首个检索词派生。同名已存在时自动加序号。" },
        limit: { type: "integer", minimum: 1, maximum: 8, description: "每个内置来源每个检索词最多取几张，默认 3。" },
        max: { type: "integer", minimum: 4, maximum: 24, description: "整块板最多收几张，默认 12。" },
        minWidth: { type: "integer", minimum: 600, maximum: 4000, description: "最小图片宽度（px），默认 1200；没有大图时降到 1000 并注明。" },
        refresh: { type: "boolean", description: "忽略缓存、换 slug 重抓（不会覆盖旧板子）。" },
        workspace: { type: "string", description: "会话工作区绝对路径（含 designs/ 的那一层）。缺省用进程 cwd；不确定就显式传。" },
      },
      required: [],
    },
  },
  {
    name: "reference_library",
    description:
      "查共享参考库：列出/搜索 designs/references/ 里已经抓过的参考板（slug、检索词、来源、张数、board.png 路径），用来复用旧板子、避免重复联网抓。复用前必须 read_image 重新看一遍。",
    inputSchema: {
      type: "object",
      properties: {
        query: { type: "string", description: "关键词（匹配 slug / 检索词 / 来源）；缺省列出全部。" },
        limit: { type: "integer", minimum: 1, maximum: 100, description: "最多返回几块，默认 20。" },
        workspace: { type: "string", description: "会话工作区绝对路径；缺省用进程 cwd。" },
      },
      required: [],
    },
  },
  {
    name: "reference_status",
    description:
      "自检联网参考能力：逐个探测 Bing 图片搜索 / Are.na / Design Reviewed / Fonts In Use / It's Nice That 是否可达，并返回工作区、脚本是否存在、共享参考库统计。新稿开工前或抓取失败时先跑一次。",
    inputSchema: {
      type: "object",
      properties: { workspace: { type: "string", description: "会话工作区绝对路径；缺省用进程 cwd。" } },
      required: [],
    },
  },
];

const HANDLERS = {
  reference_search: toolSearch,
  reference_library: toolLibrary,
  reference_status: toolStatus,
};

// ─────────────────────────────── JSON-RPC 循环 ───────────────────────────────

const write = (msg) => process.stdout.write(JSON.stringify(msg) + "\n");

const okResult = (text) => ({ content: [{ type: "text", text }], isError: false });
const errResult = (text) => ({ content: [{ type: "text", text }], isError: true });

async function handleRequest(msg) {
  const { id, method, params } = msg;
  if (method === "initialize") {
    return {
      jsonrpc: "2.0",
      id,
      result: {
        protocolVersion: (params && params.protocolVersion) || "2025-06-18",
        capabilities: { tools: { listChanged: false } },
        serverInfo: SERVER,
        instructions:
          "平面设计工坊参考图抓取服务。先 reference_search（检索词用 movement + medium + decade），命中缓存会直接返回；要复用旧板子查 reference_library；抓不动先 reference_status。",
      },
    };
  }
  if (method === "ping") return { jsonrpc: "2.0", id, result: {} };
  if (method === "tools/list") return { jsonrpc: "2.0", id, result: { tools: TOOLS } };
  if (method === "tools/call") {
    const name = params && params.name;
    const args = (params && params.arguments) || {};
    const handler = HANDLERS[name];
    if (!handler) {
      return { jsonrpc: "2.0", id, result: errResult(JSON.stringify({ ok: false, error: "unknown_tool", name })) };
    }
    try {
      const data = await handler(args);
      return { jsonrpc: "2.0", id, result: data.ok === false ? errResult(JSON.stringify(data)) : okResult(JSON.stringify(data)) };
    } catch (err) {
      log(`tool ${name} failed: ${err && err.stack ? err.stack : err}`);
      return {
        jsonrpc: "2.0",
        id,
        result: errResult(JSON.stringify({ ok: false, error: "internal_error", message: String((err && err.message) || err) })),
      };
    }
  }
  return { jsonrpc: "2.0", id, error: { code: -32601, message: `Method not found: ${method}` } };
}

const rl = readline.createInterface({ input: process.stdin, closeOnEof: true });
rl.on("line", async (line) => {
  const raw = line.replace(/^\uFEFF/, "").trim();
  if (!raw) return;
  let msg;
  try {
    msg = JSON.parse(raw);
  } catch {
    log("invalid JSON line ignored");
    return;
  }
  if (!msg || typeof msg !== "object") return;
  if (!("id" in msg)) return; // notification
  const response = await handleRequest(msg);
  if (response) write(response);
});
rl.on("close", () => process.exit(0));
log(`ready (${SERVER.name} ${SERVER.version})`);
