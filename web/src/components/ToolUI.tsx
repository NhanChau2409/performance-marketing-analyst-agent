import { makeAssistantToolUI } from "@assistant-ui/react";
import ReactECharts from "echarts-for-react";

const ICONS: Record<string, string> = {
  list_tables: "🗂️",
  describe_table: "🔍",
  query_data: "🛢️",
  render_chart: "📊",
};

const LABELS: Record<string, string> = {
  list_tables: "Listing available tables",
  describe_table: "Inspecting table schema",
  query_data: "Running SQL query",
  render_chart: "Rendering chart",
};

function ToolBlock({
  toolName,
  argsText,
  result,
  isRunning,
}: {
  toolName: string;
  argsText: string;
  result?: string;
  isRunning: boolean;
}) {
  const icon = ICONS[toolName] ?? "⚙️";
  const label = LABELS[toolName] ?? toolName;

  return (
    <details className="my-1.5 rounded-lg border border-slate-200 bg-slate-50 text-sm open:bg-white">
      <summary className="flex cursor-pointer list-none items-center gap-2 rounded-lg px-3 py-2 hover:bg-slate-100">
        {isRunning ? (
          <span className="inline-block h-3.5 w-3.5 animate-spin rounded-full border-2 border-blue-400 border-t-transparent" />
        ) : (
          <span className="text-green-600 font-bold">✓</span>
        )}
        <span>{icon}</span>
        <span className="font-medium text-slate-700">{label}</span>
        {!isRunning && (
          <span className="ml-auto text-xs text-slate-400">click to expand</span>
        )}
      </summary>

      <div className="border-t border-slate-200 px-3 py-2 space-y-2 text-xs">
        {argsText && (
          <div>
            <p className="mb-1 font-semibold uppercase tracking-wide text-slate-400">Input</p>
            <pre className="whitespace-pre-wrap break-all rounded bg-slate-50 p-2 text-slate-600 border border-slate-100">
              {argsText}
            </pre>
          </div>
        )}
        {result && (
          <div>
            <p className="mb-1 font-semibold uppercase tracking-wide text-slate-400">Result</p>
            <pre className="whitespace-pre-wrap break-all rounded bg-slate-50 p-2 text-slate-600 border border-slate-100">
              {result}
            </pre>
          </div>
        )}
      </div>
    </details>
  );
}

export const ListTablesUI = makeAssistantToolUI<Record<string, never>, string>({
  toolName: "list_tables",
  render({ argsText, result, status }) {
    return (
      <ToolBlock
        toolName="list_tables"
        argsText={argsText}
        result={typeof result === "string" ? result : undefined}
        isRunning={status.type === "running"}
      />
    );
  },
});

export const DescribeTableUI = makeAssistantToolUI<Record<string, never>, string>({
  toolName: "describe_table",
  render({ argsText, result, status }) {
    return (
      <ToolBlock
        toolName="describe_table"
        argsText={argsText}
        result={typeof result === "string" ? result : undefined}
        isRunning={status.type === "running"}
      />
    );
  },
});

export const QueryDataUI = makeAssistantToolUI<Record<string, never>, string>({
  toolName: "query_data",
  render({ argsText, result, status }) {
    return (
      <ToolBlock
        toolName="query_data"
        argsText={argsText}
        result={typeof result === "string" ? result : undefined}
        isRunning={status.type === "running"}
      />
    );
  },
});

export const RenderChartUI = makeAssistantToolUI<Record<string, never>, string>({
  toolName: "render_chart",
  render({ result, status }) {
    if (status.type === "running") {
      return (
        <div className="my-1.5 flex items-center gap-2 rounded-lg border border-slate-200 bg-slate-50 px-3 py-2 text-sm text-slate-600">
          <span className="inline-block h-3.5 w-3.5 animate-spin rounded-full border-2 border-blue-400 border-t-transparent" />
          <span>📊</span>
          <span className="font-medium">Rendering chart…</span>
        </div>
      );
    }

    if (typeof result !== "string") return null;

    let option: unknown;
    try {
      option = JSON.parse(result);
    } catch {
      return (
        <pre className="my-1.5 rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-xs text-red-600">
          {result}
        </pre>
      );
    }

    return (
      <div className="my-2 rounded-lg border border-slate-200 bg-white p-2">
        <ReactECharts
          option={option as object}
          style={{ height: 320 }}
          opts={{ renderer: "svg" }}
        />
      </div>
    );
  },
});
