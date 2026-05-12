import { useState } from 'react'
import type { ToolCall } from '../types'

const TOOL_LABELS: Record<string, string> = {
  list_tables: 'Listing tables',
  describe_table: 'Inspecting table',
  query_data: 'Running query',
}

interface Props {
  toolCall: ToolCall
}

export default function ToolCallBlock({ toolCall }: Props) {
  const [open, setOpen] = useState(false)
  const label = TOOL_LABELS[toolCall.tool] ?? toolCall.tool
  const isRunning = toolCall.status === 'running'

  return (
    <div className="my-1 rounded border border-slate-200 bg-slate-50 text-sm">
      <button
        onClick={() => setOpen(!open)}
        className="flex w-full items-center gap-2 px-3 py-2 text-left hover:bg-slate-100"
      >
        {isRunning ? (
          <span className="inline-block h-3 w-3 animate-spin rounded-full border-2 border-slate-400 border-t-transparent" />
        ) : (
          <span className="text-green-600">✓</span>
        )}
        <span className="font-medium text-slate-700">{label}</span>
        {toolCall.tool === 'query_data' && toolCall.input && !isRunning && (
          <span className="ml-auto font-mono text-xs text-slate-400 truncate max-w-xs">
            {toolCall.input.slice(0, 60)}…
          </span>
        )}
        <span className="ml-auto text-slate-400">{open ? '▲' : '▼'}</span>
      </button>

      {open && (
        <div className="border-t border-slate-200 px-3 py-2 space-y-2">
          {toolCall.input && (
            <div>
              <div className="text-xs font-semibold uppercase text-slate-400 mb-1">Input</div>
              <pre className="whitespace-pre-wrap break-all text-xs text-slate-600 bg-white rounded p-2 border border-slate-100">
                {toolCall.input}
              </pre>
            </div>
          )}
          {toolCall.output && (
            <div>
              <div className="text-xs font-semibold uppercase text-slate-400 mb-1">Output</div>
              <pre className="whitespace-pre-wrap break-all text-xs text-slate-600 bg-white rounded p-2 border border-slate-100">
                {toolCall.output}
              </pre>
            </div>
          )}
        </div>
      )}
    </div>
  )
}
