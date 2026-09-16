// Driving the MCP server over stdio, for the black-box oracle.
//
// The CLI half of the oracle reaches the binary through `uc-binary.ts`; this is
// the other half. Three feature files — mcp/surface, mcp/wrapper and
// mcp/resources — are ten rows between them and all need the same transport, so
// it is written once here rather than per file.
//
// `UC_MCP_BIN` is the seam, mirroring UC_BIN: unset it runs the committed Node
// bundle, set it runs whatever it names, which at ladder row 5 is the Swift
// server.
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { resolve } from "node:path";

const repoRoot = resolve(import.meta.dirname, "../..");

export interface JsonRpcResponse {
  jsonrpc: "2.0";
  id: number;
  result?: Record<string, unknown>;
  error?: { code: number; message: string };
}

/** A live server process, with one request/response round trip per call. */
export class McpSession {
  private readonly child: ChildProcessWithoutNullStreams;
  private readonly pending = new Map<number, (value: JsonRpcResponse) => void>();
  private buffer = "";
  private nextId = 1;

  private constructor(cwd: string, env: Record<string, string>) {
    const override = process.env.UC_MCP_BIN?.trim();
    const [command, args] = override
      ? [override, [] as string[]]
      : [process.execPath, [resolve(repoRoot, "dist/uc-mcp.js")]];
    this.child = spawn(command, args, {
      cwd,
      env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0", ...env },
      stdio: ["pipe", "pipe", "pipe"]
    }) as ChildProcessWithoutNullStreams;
    this.child.stdout.on("data", (chunk: Buffer) => this.consume(chunk.toString()));
  }

  private consume(text: string): void {
    this.buffer += text;
    let index: number;
    while ((index = this.buffer.indexOf("\n")) >= 0) {
      const line = this.buffer.slice(0, index).trim();
      this.buffer = this.buffer.slice(index + 1);
      if (!line) continue;
      let message: JsonRpcResponse;
      try {
        message = JSON.parse(line) as JsonRpcResponse;
      } catch {
        continue; // Not every line on stdout is a response; ignore the rest.
      }
      const resolveFn = this.pending.get(message.id);
      if (resolveFn) {
        this.pending.delete(message.id);
        resolveFn(message);
      }
    }
  }

  /** Start a session and complete the initialize handshake. */
  static async start(cwd: string, env: Record<string, string> = {}): Promise<McpSession> {
    const session = new McpSession(cwd, env);
    await session.request("initialize", {
      protocolVersion: "2024-11-05",
      capabilities: {},
      clientInfo: { name: "use-cases-blackbox", version: "0" }
    });
    return session;
  }

  async request(method: string, params: Record<string, unknown> = {}): Promise<JsonRpcResponse> {
    const id = this.nextId++;
    const wait = new Promise<JsonRpcResponse>((resolveFn, reject) => {
      this.pending.set(id, resolveFn);
      setTimeout(() => {
        if (this.pending.delete(id)) reject(new Error(`MCP ${method} timed out after 15s`));
      }, 15_000);
    });
    this.child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`);
    return wait;
  }

  /** The initialize handshake's advertised capabilities. */
  async capabilities(): Promise<string[]> {
    const response = await this.request("initialize", {
      protocolVersion: "2024-11-05",
      capabilities: {},
      clientInfo: { name: "use-cases-blackbox", version: "0" }
    });
    return Object.keys((response.result?.capabilities as Record<string, unknown>) ?? {}).sort();
  }

  /**
   * Call a tool and parse the CLI envelope out of its text content. The whole
   * point of the wrapper is that this is the SAME envelope the CLI emits.
   */
  async callTool<T = Record<string, unknown>>(
    name: string,
    args: Record<string, unknown>
  ): Promise<{ envelope: { command: string; ok: boolean; data: T }; raw: JsonRpcResponse }> {
    const raw = await this.request("tools/call", { name, arguments: args });
    const content = (raw.result?.content as Array<{ text: string }> | undefined)?.[0]?.text ?? "";
    return { envelope: JSON.parse(content), raw };
  }

  stop(): void {
    this.child.kill();
  }
}
