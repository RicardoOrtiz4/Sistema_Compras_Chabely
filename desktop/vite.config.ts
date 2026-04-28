import path from "node:path";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "src/renderer"),
    },
  },
  server: {
    port: 5173,
    strictPort: true,
  },
  build: {
    outDir: "dist",
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (!id.includes("node_modules")) {
            return undefined;
          }

          if (id.includes("firebase")) {
            return "vendor-firebase";
          }

          if (id.includes("react-router") || id.includes("@remix-run")) {
            return "vendor-router";
          }

          if (id.includes("lucide-react")) {
            return "vendor-icons";
          }

          if (id.includes("zustand") || id.includes("@tanstack/react-query")) {
            return "vendor-state";
          }

          if (id.includes("react") || id.includes("scheduler")) {
            return "vendor-react";
          }

          return "vendor-misc";
        },
      },
    },
  },
});
