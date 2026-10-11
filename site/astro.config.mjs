import { defineConfig } from "astro/config";

// MIRROR=1 builds the GitHub Pages copy. It is identical, but marked noindex; canonical always points at the apps URL.
const mirror = process.env.MIRROR === "1";

export default defineConfig({
  site: mirror ? "https://ashwingopalsamy.github.io" : "https://apps.ashwingopalsamy.in",
  base: "/atomberg-console/",
  trailingSlash: "always",
  compressHTML: true,
  prefetch: false,
  devToolbar: { enabled: false },
  build: {
    format: "directory",
    inlineStylesheets: "always",
  },
  // Scripts stay external so the CSP can say script-src 'self' with no inline exceptions.
  vite: { build: { assetsInlineLimit: 0 } },
});
