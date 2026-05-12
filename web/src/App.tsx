import { useState, useEffect } from "react";
import { MessageSquarePlus, MessageSquare, Trash2, Sun, Moon } from "lucide-react";
import ChatView from "./components/ChatView";

interface Thread {
  id: string;
  title: string;
}

export default function App() {
  const [threads, setThreads] = useState<Thread[]>([]);
  const [currentId, setCurrentId] = useState<string>("");
  const [dark, setDark] = useState(() => {
    return localStorage.getItem("theme") === "dark" ||
      (!localStorage.getItem("theme") && window.matchMedia("(prefers-color-scheme: dark)").matches);
  });

  useEffect(() => {
    document.documentElement.classList.toggle("dark", dark);
    localStorage.setItem("theme", dark ? "dark" : "light");
  }, [dark]);

  function newThread() {
    const id = crypto.randomUUID();
    const thread: Thread = { id, title: `Chat ${threads.length + 1}` };
    setThreads((prev) => [thread, ...prev]);
    setCurrentId(id);
  }

  function deleteThread(id: string) {
    setThreads((prev) => prev.filter((t) => t.id !== id));
    if (currentId === id) setCurrentId("");
  }

  return (
    <div className="flex h-screen overflow-hidden font-sans" style={{ background: "var(--bg-primary)", color: "var(--text-primary)" }}>
      {/* Sidebar */}
      <aside className="flex w-60 flex-shrink-0 flex-col" style={{ background: "var(--bg-sidebar)", borderRight: "1px solid var(--border)" }}>
        <div className="px-3 py-3" style={{ borderBottom: "1px solid var(--border)" }}>
          <button
            onClick={newThread}
            className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm font-medium transition-colors hover:opacity-90"
            style={{ background: "var(--bg-secondary)", color: "var(--text-primary)", border: "1px solid var(--border)" }}
          >
            <MessageSquarePlus size={15} />
            New conversation
          </button>
        </div>

        <div className="flex-1 overflow-y-auto py-2">
          {threads.length === 0 && (
            <p className="px-4 py-3 text-xs" style={{ color: "var(--text-muted)" }}>No conversations yet.</p>
          )}
          {threads.map((t) => (
            <div
              key={t.id}
              className="group flex items-center gap-1 px-2 py-1.5 mx-1 rounded-lg cursor-pointer transition-colors"
              style={{
                background: t.id === currentId ? "var(--bg-secondary)" : "transparent",
                color: t.id === currentId ? "var(--text-primary)" : "var(--text-secondary)",
              }}
              onClick={() => setCurrentId(t.id)}
            >
              <MessageSquare size={13} className="flex-shrink-0 opacity-60" />
              <span className="flex-1 truncate text-sm">{t.title}</span>
              <button
                onClick={(e) => { e.stopPropagation(); deleteThread(t.id); }}
                className="hidden group-hover:flex items-center justify-center rounded p-0.5 transition-colors"
                style={{ color: "var(--text-muted)" }}
              >
                <Trash2 size={12} />
              </button>
            </div>
          ))}
        </div>

        <div className="px-3 py-3 flex items-center justify-between" style={{ borderTop: "1px solid var(--border)" }}>
          <div>
            <p className="text-xs font-medium" style={{ color: "var(--text-secondary)" }}>Marketing Agent</p>
          </div>
          <button
            onClick={() => setDark((d) => !d)}
            className="rounded-lg p-1.5 transition-colors"
            style={{ color: "var(--text-muted)", background: "var(--bg-secondary)" }}
            title="Toggle theme"
          >
            {dark ? <Sun size={14} /> : <Moon size={14} />}
          </button>
        </div>
      </aside>

      {/* Main */}
      <main className="flex flex-1 flex-col overflow-hidden">
        {currentId ? (
          <ChatView key={currentId} threadId={currentId} />
        ) : (
          <div className="flex flex-1 flex-col items-center justify-center gap-4 text-center">
            <div className="rounded-2xl p-4" style={{ background: "var(--bg-secondary)" }}>
              <MessageSquarePlus size={28} style={{ color: "var(--text-secondary)" }} />
            </div>
            <div>
              <p className="text-base font-semibold" style={{ color: "var(--text-primary)" }}>
                Start a new conversation
              </p>
              <p className="mt-1 text-sm" style={{ color: "var(--text-muted)" }}>
                Ask anything about your campaign performance.
              </p>
            </div>
            <button
              onClick={newThread}
              className="rounded-lg px-4 py-2 text-sm font-medium transition-colors"
              style={{ background: "var(--bg-secondary)", color: "var(--text-primary)", border: "1px solid var(--border)" }}
            >
              New conversation
            </button>
          </div>
        )}
      </main>
    </div>
  );
}
