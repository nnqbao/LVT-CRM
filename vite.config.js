import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

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

export default defineConfig({
  plugins: [inlineVietnamesePdfFont(), react()],
  assetsInclude: ["**/*.ttf"],
  server: {
    allowedHosts: ["lvt.vscgroup.io.vn"],
    proxy: {
      "/api/auth": {
        target: "http://127.0.0.1:3317",
        changeOrigin: true,
      },
      "/api": {
        target: "http://127.0.0.1:3316",
        changeOrigin: true,
        ws: true,
      },
      "/.well-known": {
        target: "http://127.0.0.1:3317",
        changeOrigin: true,
      },
    },
  },
});
