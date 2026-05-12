import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import type { Message } from '../types'
import ToolCallBlock from './ToolCallBlock'

interface Props {
  message: Message
  isStreaming?: boolean
}

export default function MessageBubble({ message, isStreaming }: Props) {
  const isUser = message.role === 'user'

  if (isUser) {
    return (
      <div className="flex justify-end">
        <div className="max-w-[70%] rounded-2xl rounded-tr-sm bg-blue-600 px-4 py-2.5 text-sm text-white">
          {message.content}
        </div>
      </div>
    )
  }

  return (
    <div className="flex justify-start">
      <div className="max-w-[85%] space-y-1">
        {/* Tool calls appear above the final response */}
        {message.toolCalls.map((tc) => (
          <ToolCallBlock key={tc.id} toolCall={tc} />
        ))}

        {/* Assistant text response */}
        {(message.content || isStreaming) && (
          <div className="rounded-2xl rounded-tl-sm bg-white border border-slate-200 px-4 py-2.5 text-sm text-slate-800 shadow-sm">
            <div className="prose max-w-none">
              <ReactMarkdown remarkPlugins={[remarkGfm]}>
                {message.content}
              </ReactMarkdown>
            </div>
            {isStreaming && (
              <span className="inline-block ml-0.5 h-4 w-0.5 animate-pulse bg-slate-400" />
            )}
          </div>
        )}
      </div>
    </div>
  )
}
