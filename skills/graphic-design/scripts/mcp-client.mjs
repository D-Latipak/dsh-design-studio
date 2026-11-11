#!/usr/bin/env node
// 通用 craft MCP 客户端（技能自带，供 Test-Design / Inspect-Render 调用）。
// 用法：
//   node mcp-client.mjs --session steps.json [--cli <exe>] [--cli-args '["mcp"]']
// steps.json: [{"tool":"open_document","arguments":{"path":"…"}}, {"tool":"inspect_document","arguments":{}}]
// 输出：JSON 数组 [{index, tool, ok, result|error}]，图片结果只给 base64 长度。
import { spawn } from "node:child_process";
import readline from "node:readline";
import { readFileSync } from "node:fs";
import process from "node:process";

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    if (!argv[i].startsWith("--")) continue;
    out[argv[i].slice(2)] = argv[i + 1] && !argv[i + 1].startsWith("--") ? argv[++i] : true;
  }
  return out;
}

const args = parseArgs(process.argv.slice(2));
const CLI =
  args.cli ||
  process.env.DESIGNCRAFT_CLI ||
  "C:\\Program Files\\ArtCraft\\DesignCraft\\designcraft-cli.exe";
const cliArgs = args["cli-args"] ? JSON.parse(args["cli-args"]) : ["mcp"];
const stepsPath = args.session;
if (!stepsPath) {
  console.error("usage: node mcp-client.mjs --session steps.json [--cli exe] [--cli-args json]");
  process.exit(2);
}
const steps = JSON.parse(readFileSync(stepsPath, "utf8").replace(/^\uFEFF/, ""));

const child = spawn(CLI, cliArgs, { stdio: ["pipe", "pipe", "ignore"] });
const rl = readline.createInterface({ input: child.stdout });
const pending = new Map();
let nextId = 1;

const send = (m) => child.stdin.write(JSON.stringify(m) + "\n");
function request(method, params) {
  const id = nextId++;
  send({ jsonrpc: "2.0", id, method, params });
  return new Promise((resolve, reject) => {
    // 定时器必须清掉，否则 Node 会被挂起的 setTimeout 拖到最后才退出（表现为“卡住 240s”）
    const timer = setTimeout(() => {
      if (pending.has(id)) {
        pending.delete(id);
        reject(new Error(`timeout: ${method}`));
      }
    }, 240000);
    pending.set(id, {
      resolve: (v) => { clearTimeout(timer); resolve(v); },
      reject: (e) => { clearTimeout(timer); reject(e); },
    });
  });
}
rl.on("line", (line) => {
  if (!line.trim()) return;
  let msg;
  try {
    msg = JSON.parse(line);
  } catch {
    return;
  }
  if (msg.id && pending.has(msg.id)) {
    const p = pending.get(msg.id);
    pending.delete(msg.id);
    msg.error ? p.reject(new Error(JSON.stringify(msg.error))) : p.resolve(msg.result);
  }
});

const summarize = (r) => {
  const c = structuredClone(r);
  if (Array.isArray(c.content)) {
    c.content = c.content.map((x) =>
      x.type === "image" ? { type: "image", mimeType: x.mimeType, base64Chars: (x.data || "").length } : x,
    );
  }
  return c;
};

const main = async () => {
  await request("initialize", {
    protocolVersion: "2025-06-18",
    capabilities: {},
    clientInfo: { name: "dsh-design-qa", version: "1.0.0" },
  });
  send({ jsonrpc: "2.0", method: "notifications/initialized" });
  const out = [];
  for (let i = 0; i < steps.length; i++) {
    const s = steps[i];
    try {
      const res = await request("tools/call", { name: s.tool, arguments: s.arguments || {} });
      out.push({ index: i, tool: s.tool, ok: !res.isError, result: summarize(res) });
    } catch (e) {
      out.push({ index: i, tool: s.tool, ok: false, error: e.message });
    }
  }
  process.stdout.write(JSON.stringify(out), () => {
    child.stdin.end();
    child.kill();
    process.exit(0);
  });
};

main().catch((e) => {
  process.stderr.write(String(e && e.message));
  child.kill();
  process.exit(1);
});
