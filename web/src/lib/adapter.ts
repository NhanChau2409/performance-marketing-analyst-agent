import type { ChatModelAdapter } from "@assistant-ui/react";

type ToolState = {
  id: string;
  toolName: string;
  argsText: string;
  result?: string;
};

function buildContent(text: string, tools: ToolState[]) {
  const parts: object[] = [];

  if (text) {
    parts.push({ type: "text", text });
  }

  for (const tc of tools) {
    const part: Record<string, unknown> = {
      type: "tool-call",
      toolCallId: tc.id,
      toolName: tc.toolName,
      args: {},
      argsText: tc.argsText,
    };
    if (tc.result !== undefined) {
      part.result = tc.result;
    }
    parts.push(part);
  }

  if (parts.length === 0) {
    parts.push({ type: "text", text: "" });
  }

  return parts as Parameters<typeof Array.prototype.push>[0][];
}

async function* readSSE(
  body: ReadableStream<Uint8Array>,
  abortSignal: AbortSignal,
): AsyncGenerator<Record<string, string>> {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";

  try {
    while (true) {
      if (abortSignal.aborted) break;
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split("\n");
      buffer = lines.pop() ?? "";

      for (const line of lines) {
        if (!line.startsWith("data: ")) continue;
        const raw = line.slice(6).trim();
        if (!raw) continue;
        try {
          yield JSON.parse(raw) as Record<string, string>;
        } catch {
          // skip malformed lines
        }
      }
    }
  } finally {
    reader.releaseLock();
  }
}

export function createAdapter(threadId: string): ChatModelAdapter {
  return {
    async *run({ messages, abortSignal }) {
      const lastMsg = messages[messages.length - 1];
      const userText = lastMsg.content
        .filter((p) => p.type === "text")
        .map((p) => (p as { text: string }).text)
        .join("");

      let text = "";
      const toolCalls: ToolState[] = [];

      // Kick off the initial request
      const response = await fetch("/api/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: userText, thread_id: threadId }),
        signal: abortSignal,
      });
      if (!response.ok) throw new Error(`API error ${response.status}`);
      if (!response.body) throw new Error("No response body");

      // Loop: process events, auto-approve every interrupt, until "done"
      let stream: AsyncGenerator<Record<string, string>> = readSSE(response.body, abortSignal);

      let running = true;
      while (running) {
        let interrupted = false;
        for await (const event of stream) {
          if (event.type === "token") {
            text += event.content;
            yield { content: buildContent(text, toolCalls) as never };

          } else if (event.type === "tool_start") {
            toolCalls.push({
              id: `${event.tool}-${Date.now()}`,
              toolName: event.tool,
              argsText: event.input ?? "",
            });
            yield { content: buildContent(text, toolCalls) as never };

          } else if (event.type === "tool_end") {
            const tc = [...toolCalls]
              .reverse()
              .find((t) => t.toolName === event.tool && t.result === undefined);
            if (tc) {
              tc.result = event.output ?? "";
              yield { content: buildContent(text, toolCalls) as never };
            }

          } else if (event.type === "interrupt") {
            const resumeResp = await fetch("/api/resume", {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ thread_id: threadId, action: "approve" }),
              signal: abortSignal,
            });
            if (!resumeResp.ok || !resumeResp.body) { running = false; break; }
            stream = readSSE(resumeResp.body, abortSignal);
            interrupted = true;
            break;

          } else if (event.type === "done" || event.type === "error") {
            running = false;
            break;
          }
        }
        if (!interrupted) running = false;
      }
    },
  };
}
