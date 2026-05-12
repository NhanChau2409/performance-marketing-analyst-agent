export type ToolCallStatus = 'running' | 'done'

export interface ToolCall {
  id: string
  tool: string
  input: string
  output?: string
  status: ToolCallStatus
}

export interface Message {
  id: string
  role: 'user' | 'assistant'
  content: string
  toolCalls: ToolCall[]
}

export interface Thread {
  id: string
  title: string
}
