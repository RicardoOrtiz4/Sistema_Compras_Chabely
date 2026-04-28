import type { Config } from "tailwindcss";

export default {
  content: ["./index.html", "./src/renderer/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        ink: "#0f172a",
        canvas: "#f3f4f6",
        panel: "#ffffff",
        line: "#d7dce5",
        accent: "#1d4ed8",
        accentSoft: "#dbeafe",
        success: "#15803d",
        warning: "#b45309",
        danger: "#b91c1c",
      },
      fontFamily: {
        sans: ["Segoe UI", "Tahoma", "Geneva", "Verdana", "sans-serif"],
      },
      boxShadow: {
        shell: "0 16px 40px rgba(15, 23, 42, 0.08)",
      },
    },
  },
  plugins: [],
} satisfies Config;
