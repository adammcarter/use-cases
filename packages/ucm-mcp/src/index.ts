#!/usr/bin/env node
import { realpathSync } from "node:fs";
import { createInterface } from "node:readline";
import { stdin, stdout } from "node:process";
import { fileURLToPath } from "node:url";
import { callMcpTool, mcpTools } from "./tools.js";

type UcmCoreModule = typeof import("@presentation-skills/ucm-core");

const { getVersionInfo } = await loadUcmCore();

async function loadUcmCore(): Promise<UcmCoreModule> {
  try {
    return await import("@presentation-skills/ucm-core");
  } catch (error) {
    if (!isMissingCorePackage(error)) {
      throw error;
    }
    const bundledCoreSpecifier = "../../ucm-core/dist/index.js";
    return await import(bundledCoreSpecifier) as UcmCoreModule;
  }
}

function isMissingCorePackage(error: unknown): boolean {
  return error instanceof Error && "code" in error && error.code === "ERR_MODULE_NOT_FOUND" && error.message.includes("@presentation-skills/ucm-core");
}

type JsonRpcRequest = {
  jsonrpc: "2.0";
  id?: string | number | null;
  method?: string;
  params?: unknown;
};

type JsonRpcResponse = {
  jsonrpc: "2.0";
  id: string | number | null;
  result?: unknown;
  error?: {
    code: number;
    message: string;
  };
};

export function handleMcpMessage(message: JsonRpcRequest): JsonRpcResponse | null {
  if (message.method === "notifications/initialized") {
    return null;
  }

  const id = message.id ?? null;

  if (message.method === "initialize") {
    return {
      jsonrpc: "2.0",
      id,
      result: {
        protocolVersion: "2024-11-05",
        capabilities: {
          tools: {}
        },
        serverInfo: getVersionInfo()
      }
    };
  }

  if (message.method === "tools/list") {
    return {
      jsonrpc: "2.0",
      id,
      result: {
        tools: mcpTools
      }
    };
  }

  if (message.method === "tools/call") {
    const params = isRecord(message.params) ? message.params : {};
    const name = typeof params.name === "string" ? params.name : "";
    const args = isRecord(params.arguments) ? params.arguments : {};
    const envelope = callMcpTool(name, args);
    return {
      jsonrpc: "2.0",
      id,
      result: {
        content: [{ type: "text", text: JSON.stringify(envelope) }],
        structuredContent: envelope,
        isError: false
      }
    };
  }

  return {
    jsonrpc: "2.0",
    id,
    error: {
      code: -32601,
      message: `Method not found: ${message.method ?? "<missing>"}`
    }
  };
}

export function startStdioServer(): void {
  const lines = createInterface({
    input: stdin,
    crlfDelay: Infinity,
    terminal: false
  });

  lines.on("line", (line: string) => {
    if (!line.trim()) {
      return;
    }

    let parsed: JsonRpcRequest;
    try {
      parsed = JSON.parse(line) as JsonRpcRequest;
    } catch {
      const response: JsonRpcResponse = {
        jsonrpc: "2.0",
        id: null,
        error: {
          code: -32700,
          message: "Parse error"
        }
      };
      stdout.write(`${JSON.stringify(response)}\n`);
      return;
    }

    const response = handleMcpMessage(parsed);
    if (response) {
      stdout.write(`${JSON.stringify(response)}\n`);
    }
  });
}

function isEntrypoint(): boolean {
  if (!process.argv[1]) {
    return false;
  }

  try {
    return realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

if (isEntrypoint()) {
  startStdioServer();
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
