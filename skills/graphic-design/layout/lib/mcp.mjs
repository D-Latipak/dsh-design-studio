#!/usr/bin/env node
// 最小 MCP 客户端（stdio + 换行分隔 JSON-RPC），只依赖 node 内置模块。
// 由 layout.mjs 使用：一个进程 = 一份文档 = 一次完整排版会话。
//
// 关键点：DesignCraft 的 MCP 服务在进程内持有文档状态，
// 所以「建文档 → 量文字 → 排位置 → 导出」必须发生在同一个进程里。
import { spawn } from "node:child_process";
import readline from "node:readline";
import process from "node:process";

export const DEFAULT_CLI =
  process.env.DESIGNCRAFT_CLI ||
  "C:\\Program Files\\ArtCraft\\DesignCraft\\designcraft-cli.exe";

export class DesignCraft {
  constructor(opts = {}) {
    this.cli = opts.cli || DEFAULT_CLI;
    this.timeout = opts.timeout ?? 120000;
    this.seq = 1;
    this.pending = new Map();
    this.child = spawn(this.cli, ["mcp"], { stdio: ["pipe", "pipe", "pipe"] });
    this.stderr = "";
    this.child.stderr.on("data", (d) => {
      this.stderr += d.toString();
      if (this.stderr.length > 20000) this.stderr = this.stderr.slice(-20000);
    });
    this.rl = readline.createInterface({ input: this.child.stdout });
    this.rl.on("line", (line) => this.#onLine(line));
    this.child.on("exit", (code) => {
      for (const [, p] of this.pending) p.reject(new Error(`designcraft-cli exited (${code})`));
      this.pending.clear();
    });
  }

  #onLine(line) {
    if (!line.trim()) return;
    let msg;
    try {
      msg = JSON.parse(line);
    } catch {
      return;
    }
    const p = msg.id && this.pending.get(msg.id);
    if (!p) return;
    this.pending.delete(msg.id);
    if (msg.error) p.reject(new Error(msg.error.message || JSON.stringify(msg.error)));
    else p.resolve(msg.result);
  }

  request(method, params) {
    const id = this.seq++;
    this.child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      const t = setTimeout(() => {
        if (this.pending.has(id)) {
          this.pending.delete(id);
          reject(new Error(`timeout: ${method}`));
        }
      }, this.timeout);
      const done = this.pending.get(id);
      done.resolve = (v) => (clearTimeout(t), resolve(v));
      done.reject = (e) => (clearTimeout(t), reject(e));
    });
  }

  async init() {
    await this.request("initialize", {
      protocolVersion: "2025-06-18",
      capabilities: {},
      clientInfo: { name: "dsh-layout", version: "1.0.0" },
    });
    this.child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
    return this;
  }

  async tool(name, args = {}) {
    const res = await this.request("tools/call", { name, arguments: args });
    if (res.isError) {
      const t = (res.content || []).filter((c) => c.type === "text").map((c) => c.text).join("\n");
      throw new Error(`${name}: ${t || "isError"}`);
    }
    return res;
  }

  /** 调工具并把 text content 解析成 JSON（解析不了就返回原文） */
  async json(name, args = {}) {
    const res = await this.tool(name, args);
    const text = (res.content || []).filter((c) => c.type === "text").map((c) => c.text).join("\n");
    try {
      return JSON.parse(text);
    } catch {
      return text;
    }
  }

  async batch(commands) {
    if (!commands.length) return { completed: 0, results: [] };
    return this.json("batch", { commands });
  }

  close() {
    try {
      this.child.stdin.end();
      this.child.kill();
    } catch {
      /* ignore */
    }
  }
}
