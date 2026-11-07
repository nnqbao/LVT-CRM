import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { convexLocalPorts } from "./scripts/lib/convex-local-ports.mjs";

function inlineVietnamesePdfFont() {
  return {
    name: "inline-vietnamese-pdf-font",
    enforce: "pre",
    /**
     * @param {string} id
     */
    load(id) {
      const filePath = id.split("?")[0].replace(/\\/g, "/");
      if (!filePath.endsWith("/src/homeroom/vietnamesePdfFont.js")) return null;
      const ttfPath = resolve(process.cwd(), "src/assets/fonts/NotoSans-Regular.ttf");
      const base64 = readFileSync(ttfPath).toString("base64");
      return `
export function loadVietnamesePdfFontBytes() {
  const binary = atob(${JSON.stringify(base64)});
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes;
}
`;
    },
  };
}

// Dev proxy to this checkout's self-hosted Convex, only when it has a reservation in the
// untracked infra/convex-local/.env (ports differ per checkout; see that file's .env.example).
const localConvex = convexLocalPorts();

export default defineConfig({
  plugins: [inlineVietnamesePdfFont(), react()],
  assetsInclude: ["**/*.ttf"],
  server: {
    allowedHosts: ["lvt.vscgroup.io.vn"],
    proxy: localConvex
      ? {
          "/api/auth": { target: localConvex.site, changeOrigin: true },
          "/api": { target: localConvex.backend, changeOrigin: true, ws: true },
          "/.well-known": { target: localConvex.site, changeOrigin: true },
        }
      : undefined,
  },
});
