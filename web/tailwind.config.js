import animate from "tailwindcss-animate";
import typography from "@tailwindcss/typography";

/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      typography: {
        chat: {
          css: {
            "--tw-prose-body": "#1e293b",
            "--tw-prose-headings": "#0f172a",
            "--tw-prose-bold": "#0f172a",
            "--tw-prose-code": "#4f46e5",
            "--tw-prose-pre-bg": "#f8fafc",
            "--tw-prose-pre-code": "#334155",
            "--tw-prose-quotes": "#475569",
            "--tw-prose-quote-borders": "#e2e8f0",
            "--tw-prose-links": "#2563eb",
            "--tw-prose-th-borders": "#e2e8f0",
            "--tw-prose-td-borders": "#f1f5f9",
            fontSize: "0.875rem",
            lineHeight: "1.65",
            maxWidth: "none",
            p: { marginTop: "0.4em", marginBottom: "0.4em" },
            "ul, ol": { marginTop: "0.4em", marginBottom: "0.4em" },
            li: { marginTop: "0.1em", marginBottom: "0.1em" },
            "h1,h2,h3,h4": { marginTop: "0.8em", marginBottom: "0.3em", fontWeight: "600" },
            pre: { borderRadius: "0.5rem", padding: "0.75rem 1rem", fontSize: "0.8rem" },
            code: {
              borderRadius: "0.25rem",
              padding: "0.15em 0.35em",
              backgroundColor: "#eef2ff",
              fontWeight: "500",
              fontSize: "0.8rem",
            },
            "code::before": { content: '""' },
            "code::after": { content: '""' },
            table: { fontSize: "0.8rem" },
            th: { backgroundColor: "#f8fafc", fontWeight: "600" },
            "thead th": { padding: "0.5rem 0.75rem" },
            "tbody td": { padding: "0.4rem 0.75rem" },
            blockquote: { fontStyle: "normal", borderLeftWidth: "3px" },
          },
        },
      },
    },
  },
  plugins: [animate, typography],
}
