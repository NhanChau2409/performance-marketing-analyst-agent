import { useState, useRef, useEffect } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import ReactECharts from "echarts-for-react";
import { Prism as SyntaxHighlighter } from "react-syntax-highlighter";
import { oneDark } from "react-syntax-highlighter/dist/esm/styles/prism";
import { format as formatSQL } from "sql-formatter";
import { ArrowUp, Table2, ScanText, Code2, BarChart2, Settings2, Check, ChevronDown, type LucideIcon } from "lucide-react";

// ── Types ────────────────────────────────────────────────────────────────────

type ToolCall = { tool: string; input: string; output: string };

type Message = {
  role: "user" | "assistant";
  text: string;
  charts: object[];
  toolCalls: ToolCall[];
};

interface Props { threadId: string }

// ── Tool meta ─────────────────────────────────────────────────────────────────

const TOOL_META: Record<string, { Icon: LucideIcon; label: string }> = {
  list_tables:    { Icon: Table2,    label: "Listed tables" },
  describe_table: { Icon: ScanText,  label: "Described table" },
  query_data:     { Icon: Code2,     label: "Ran SQL query" },
  render_chart:   { Icon: BarChart2, label: "Rendered chart" },
};
function toolMeta(name: string) { return TOOL_META[name] ?? { Icon: Settings2, label: name }; }

// ── Tool call helpers ─────────────────────────────────────────────────────────

function parseInput(raw: string): Record<string, unknown> {
  try { return JSON.parse(raw); } catch { return {}; }
}

function extractSQL(raw: string): string | null {
  try {
    const args = JSON.parse(raw);
    if (typeof args.sql === "string")
      return formatSQL(args.sql, { language: "sql", keywordCase: "upper" });
  } catch {}
  return null;
}

function OutputTable({ text }: { text: string }) {
  const lines = text.trim().split("\n");
  const tableLines = lines.filter((l) => l.includes("|"));
  if (tableLines.length < 2)
    return <pre style={{ color: "var(--text-secondary)" }} className="whitespace-pre-wrap font-mono text-[11px] leading-relaxed">{text}</pre>;

  const parse = (line: string) =>
    line.split("|").map((c) => c.trim()).filter((_, i, a) => i > 0 && i < a.length - 1);
  const [header, , ...rows] = tableLines;
  const headers = parse(header);
  const dataRows = rows.map(parse);

  return (
    <div className="overflow-x-auto text-[11px]">
      <table className="w-full border-collapse">
        <thead>
          <tr>
            {headers.map((h, i) => (
              <th key={i} className="pb-1.5 pr-4 text-left font-medium whitespace-nowrap" style={{ color: "var(--text-muted)", borderBottom: "1px solid var(--border)" }}>{h}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {dataRows.map((row, ri) => (
            <tr key={ri}>
              {row.map((cell, ci) => (
                <td key={ci} className="py-1 pr-4 font-mono" style={{ color: "var(--text-primary)", borderBottom: "1px solid var(--border)" }}>{cell}</td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// ── ListTablesOutput ──────────────────────────────────────────────────────────

const PLATFORM_PREFIX: Record<string, string> = {
  google: "Google", meta: "Meta", tiktok: "TikTok",
};

function ListTablesOutput({ text }: { text: string }) {
  const entries = text.split("\n").flatMap((line) => {
    const m = line.match(/[-•]\s+([\w]+):\s+([\d,]+)\s+rows?/);
    return m ? [{ name: m[1], count: m[2] }] : [];
  });

  if (entries.length === 0)
    return <pre className="font-mono text-[11px] leading-relaxed" style={{ color: "var(--text-secondary)" }}>{text}</pre>;

  const groups: Record<string, typeof entries> = {};
  for (const e of entries) {
    const prefix = Object.keys(PLATFORM_PREFIX).find((p) => e.name.startsWith(p)) ?? "other";
    (groups[prefix] ??= []).push(e);
  }

  return (
    <div className="space-y-3">
      {Object.entries(groups).map(([platform, tables]) => (
        <div key={platform}>
          <p className="text-[10px] font-semibold uppercase tracking-widest mb-1.5" style={{ color: "var(--text-muted)" }}>
            {PLATFORM_PREFIX[platform] ?? platform}
          </p>
          <div className="space-y-0.5">
            {tables.map((t) => (
              <div key={t.name} className="flex items-baseline justify-between">
                <span className="font-mono text-[11px]" style={{ color: "var(--text-secondary)" }}>{t.name}</span>
                <span className="text-[10px] tabular-nums ml-4" style={{ color: "var(--text-muted)" }}>{t.count}</span>
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}

function ArgBadges({ args }: { args: Record<string, unknown> }) {
  const entries = Object.entries(args);
  if (entries.length === 0)
    return <span className="text-[11px] italic" style={{ color: "var(--text-muted)" }}>no arguments</span>;
  return (
    <div className="flex flex-wrap gap-1.5">
      {entries.map(([k, v]) => (
        <span key={k} className="inline-flex items-center gap-1 rounded-md px-2 py-1 text-[11px] font-mono" style={{ background: "var(--bg-primary)", border: "1px solid var(--border)" }}>
          <span style={{ color: "#a78bfa" }} className="font-semibold">{k}</span>
          <span style={{ color: "var(--text-muted)" }}>=</span>
          <span style={{ color: "var(--text-primary)" }}>{String(v)}</span>
        </span>
      ))}
    </div>
  );
}

function ToolCallList({ calls }: { calls: ToolCall[] }) {
  if (calls.length === 0) return null;
  return (
    <div className="mb-3 space-y-1.5">
      {calls.map((tc, i) => {
        const { Icon, label } = toolMeta(tc.tool);
        const isSQL = tc.tool === "query_data";
        const formattedSQL = isSQL ? extractSQL(tc.input) : null;
        const args = parseInput(tc.input);
        const hasOutput = !!tc.output && tc.tool !== "render_chart";
        const isTableList = tc.tool === "list_tables" && hasOutput;
        const isTableOutput = !isTableList && hasOutput && tc.output.includes("|");

        return (
          <details key={i} className="rounded-xl text-xs overflow-hidden" style={{ border: "1px solid var(--border)", background: "var(--bg-secondary)" }}>
            <summary className="flex cursor-pointer list-none items-center gap-1.5 px-3 py-2 transition-colors select-none" style={{ color: "var(--text-secondary)" }}>
              <Check size={11} strokeWidth={2.5} style={{ color: "var(--text-muted)", flexShrink: 0 }} />
              <Icon size={12} strokeWidth={1.75} style={{ color: "var(--text-muted)", flexShrink: 0 }} />
              <span className="font-medium text-[11px]">{label}</span>
              <ChevronDown size={11} strokeWidth={2} className="ml-auto" style={{ color: "var(--text-muted)" }} />
            </summary>

            <div style={{ borderTop: "1px solid var(--border)" }} className="divide-y" >
              <div className="px-3 py-2.5">
                <p className="text-[10px] font-semibold uppercase tracking-widest mb-2" style={{ color: "var(--text-muted)" }}>Input</p>
                {isSQL && formattedSQL ? (
                  <SyntaxHighlighter
                    language="sql"
                    style={oneDark}
                    customStyle={{ margin: 0, borderRadius: "0.5rem", fontSize: "11px", lineHeight: "1.65", maxHeight: "260px", overflowY: "auto" }}
                    wrapLongLines={false}
                  >
                    {formattedSQL}
                  </SyntaxHighlighter>
                ) : (
                  <ArgBadges args={args} />
                )}
              </div>

              {hasOutput && (
                <div className="px-3 py-2.5">
                  <p className="text-[10px] font-semibold uppercase tracking-widest mb-2" style={{ color: "var(--text-muted)" }}>Output</p>
                  <div className="max-h-64 overflow-y-auto">
                    {isTableList ? (
                      <ListTablesOutput text={tc.output} />
                    ) : isTableOutput ? (
                      <OutputTable text={tc.output} />
                    ) : (
                      <pre className="whitespace-pre-wrap font-mono text-[11px] leading-relaxed rounded-lg p-2" style={{ background: "var(--bg-primary)", border: "1px solid var(--border)", color: "var(--text-secondary)" }}>{tc.output}</pre>
                    )}
                  </div>
                </div>
              )}
            </div>
          </details>
        );
      })}
    </div>
  );
}

// ── Markdown renderer ─────────────────────────────────────────────────────────

function AssistantMarkdown({ text }: { text: string }) {
  return (
    <ReactMarkdown
      remarkPlugins={[remarkGfm]}
      components={{
        p: ({ children }) => <p className="my-1 leading-7 text-sm" style={{ color: "var(--text-primary)" }}>{children}</p>,
        table: ({ children }) => (
          <div className="overflow-x-auto my-3">
            <table className="w-full text-sm border-collapse">{children}</table>
          </div>
        ),
        th: ({ children }) => (
          <th className="pb-1.5 pr-5 text-left text-xs font-medium" style={{ color: "var(--text-muted)", borderBottom: "1px solid var(--border)" }}>{children}</th>
        ),
        td: ({ children }) => (
          <td className="py-1.5 pr-5 text-sm" style={{ color: "var(--text-primary)", borderBottom: "1px solid var(--border)" }}>{children}</td>
        ),
        code: ({ inline, children, ...props }: { inline?: boolean; children?: React.ReactNode }) =>
          inline ? (
            <code className="rounded px-1 py-0.5 font-mono text-[12px]" style={{ background: "var(--code-bg)", color: "var(--code-text)" }} {...props}>{children}</code>
          ) : (
            <code className="block font-mono text-[12px]" style={{ color: "var(--code-text)" }} {...props}>{children}</code>
          ),
        pre: ({ children }) => (
          <pre className="rounded-lg px-3 py-2.5 overflow-x-auto text-[12px] leading-relaxed my-2" style={{ background: "var(--code-bg)" }}>{children}</pre>
        ),
        ul: ({ children }) => <ul className="my-1.5 space-y-0.5 pl-1" style={{ color: "var(--text-primary)" }}>{children}</ul>,
        ol: ({ children }) => <ol className="my-1.5 space-y-0.5 pl-1 list-decimal list-inside" style={{ color: "var(--text-primary)" }}>{children}</ol>,
        li: ({ children }) => (
          <li className="flex gap-2 text-sm leading-6">
            <span style={{ color: "var(--text-muted)" }} className="select-none mt-0.5">·</span>
            <span>{children}</span>
          </li>
        ),
        strong: ({ children }) => <strong className="font-semibold" style={{ color: "var(--text-primary)" }}>{children}</strong>,
        h1: ({ children }) => <h1 className="text-sm font-semibold mt-4 mb-1" style={{ color: "var(--text-primary)" }}>{children}</h1>,
        h2: ({ children }) => <h2 className="text-sm font-semibold mt-3 mb-1" style={{ color: "var(--text-primary)" }}>{children}</h2>,
        h3: ({ children }) => <h3 className="text-sm font-medium mt-2 mb-0.5" style={{ color: "var(--text-secondary)" }}>{children}</h3>,
        blockquote: ({ children }) => (
          <blockquote className="pl-3 my-1.5 text-sm" style={{ borderLeft: "2px solid var(--border)", color: "var(--text-muted)" }}>{children}</blockquote>
        ),
        hr: () => <hr className="my-3" style={{ borderColor: "var(--border)" }} />,
        a: ({ href, children }) => (
          <a href={href} className="underline underline-offset-2" style={{ color: "var(--text-secondary)" }} target="_blank" rel="noreferrer">{children}</a>
        ),
      }}
    >
      {text}
    </ReactMarkdown>
  );
}

// ── Suggestions ───────────────────────────────────────────────────────────────

const SUGGESTIONS = [
  "What are the top 3 campaigns by ROAS?",
  "Compare spend vs revenue across all platforms",
  "Show daily spend over the last 30 days as a line chart",
  "Compare ROAS across platforms as a bar chart",
];

// ── ChatView ──────────────────────────────────────────────────────────────────

export default function ChatView({ threadId }: Props) {
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState("");
  const [busy, setBusy] = useState(false);
  const bottomRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, busy]);

  async function send(text?: string) {
    const msg = (text ?? input).trim();
    if (!msg || busy) return;
    setInput("");
    setMessages((prev) => [...prev, { role: "user", text: msg, charts: [], toolCalls: [] }]);
    setBusy(true);
    try {
      const res = await fetch("/api/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: msg, thread_id: threadId }),
      });
      if (!res.ok) throw new Error(`Server error ${res.status}`);
      const data = await res.json();
      setMessages((prev) => [
        ...prev,
        {
          role: "assistant",
          text: (data.text as string) ?? "",
          charts: (data.charts as object[]) ?? [],
          toolCalls: (data.tool_calls as ToolCall[]) ?? [],
        },
      ]);
    } catch (e) {
      setMessages((prev) => [
        ...prev,
        { role: "assistant", text: `Error: ${e instanceof Error ? e.message : "unknown"}`, charts: [], toolCalls: [] },
      ]);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex flex-col h-full" style={{ background: "var(--bg-primary)" }}>
      {/* Messages */}
      <div className="flex-1 overflow-y-auto px-4 py-6">
        <div className="max-w-2xl mx-auto space-y-6">
          {messages.length === 0 && !busy && (
            <div className="flex flex-col items-center justify-center h-[60vh] gap-4 text-center">
              <p className="text-sm" style={{ color: "var(--text-muted)" }}>Ask me anything about your campaign performance.</p>
              <div className="flex flex-wrap justify-center gap-2">
                {SUGGESTIONS.map((s) => (
                  <button
                    key={s}
                    onClick={() => send(s)}
                    className="rounded-full px-3 py-1.5 text-xs transition-colors"
                    style={{ border: "1px solid var(--border)", background: "var(--bg-secondary)", color: "var(--text-secondary)" }}
                  >
                    {s}
                  </button>
                ))}
              </div>
            </div>
          )}

          {messages.map((msg, i) => (
            <div key={i} className={`flex ${msg.role === "user" ? "justify-end" : "justify-start"}`}>
              {msg.role === "user" ? (
                <div className="max-w-[75%] rounded-2xl px-4 py-2.5 text-sm leading-relaxed" style={{ background: "var(--user-bubble)", color: "var(--user-bubble-text)" }}>
                  {msg.text}
                </div>
              ) : (
                <div className="w-full text-sm">
                  <ToolCallList calls={msg.toolCalls} />
                  {msg.text && <AssistantMarkdown text={msg.text} />}
                  {msg.charts.map((chart, j) => (
                    <div key={j} className="mt-3 rounded-xl p-2" style={{ border: "1px solid var(--border)", background: "var(--bg-secondary)" }}>
                      <ReactECharts option={chart} style={{ height: 320 }} opts={{ renderer: "svg" }} />
                    </div>
                  ))}
                </div>
              )}
            </div>
          ))}

          {busy && (
            <div className="flex justify-start">
              <div className="flex items-center gap-2 text-sm" style={{ color: "var(--text-muted)" }}>
                <span className="inline-block h-3 w-3 animate-spin rounded-full border-2 border-blue-400 border-t-transparent" />
                Thinking…
              </div>
            </div>
          )}

          <div ref={bottomRef} />
        </div>
      </div>

      {/* Input bar — ChatGPT style */}
      <div className="px-4 pb-4 pt-2">
        <div className="max-w-2xl mx-auto">
          <div className="flex items-end gap-2 rounded-2xl px-4 py-3" style={{ background: "var(--bg-input)", border: "1px solid var(--border)" }}>
            <textarea
              rows={1}
              className="flex-1 resize-none bg-transparent text-sm outline-none leading-relaxed"
              style={{ color: "var(--text-primary)", maxHeight: "160px" }}
              placeholder="Ask about campaigns, spend, ROAS…"
              value={input}
              onChange={(e) => {
                setInput(e.target.value);
                e.target.style.height = "auto";
                e.target.style.height = `${e.target.scrollHeight}px`;
              }}
              onKeyDown={(e) => {
                if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); send(); }
              }}
              disabled={busy}
            />
            <button
              onClick={() => send()}
              disabled={busy || !input.trim()}
              className="flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-lg transition-colors disabled:opacity-30"
              style={{ background: input.trim() && !busy ? "var(--text-primary)" : "var(--bg-secondary)", color: input.trim() && !busy ? "var(--bg-primary)" : "var(--text-muted)" }}
            >
              <ArrowUp size={16} />
            </button>
          </div>
          <p className="mt-2 text-center text-[11px]" style={{ color: "var(--text-muted)" }}>
            Shift+Enter for new line
          </p>
        </div>
      </div>
    </div>
  );
}
