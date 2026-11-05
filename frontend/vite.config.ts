import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import path from "path";

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: { "@": path.resolve(__dirname, "./src") },
  },
  build: {
    outDir: "../public",
    emptyOutDir: false, // don't wipe Rails' public/ error pages
  },
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./src/test/setup.ts"],
    coverage: {
      provider: "v8",
      reporter: ["text", "html", "json-summary"],
      include: ["src/**/*.{ts,tsx}"],
      exclude: [
        "src/**/*.test.{ts,tsx}",
        "src/test/**",
        "src/main.tsx",
        "src/vite-env.d.ts",
        "src/**/*.d.ts",
      ],
    },
  },
  server: {
    port: 5173,
    host: true,
    proxy: {
      "/api": { target: process.env.API_TARGET ?? "http://localhost:3001", changeOrigin: true },
      "/api-docs": { target: process.env.API_TARGET ?? "http://localhost:3001", changeOrigin: true },
      // Sign in with fog: the OpenID start/callback/link endpoints live on
      // Rails. The Host header stays this server's, so the redirect URI Rails
      // builds from it brings the browser back here.
      "/auth/oidc": { target: process.env.API_TARGET ?? "http://localhost:3001", changeOrigin: false },
      "/cable": {
        target: (process.env.API_TARGET ?? "http://localhost:3001").replace(/^http/, "ws"),
        ws: true,
        changeOrigin: true,
      },
    },
  },
});
