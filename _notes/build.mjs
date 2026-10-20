// Bundles src/ into ../nox/.local/lib/nox/notes-app/web (one script + one stylesheet, loaded from
// file:// by the Electron window). The output is committed, so the app runs without node or npm;
// rebuild after changing src/ or bumping @milkdown/crepe:  npm ci && npm run build
import { build } from "esbuild";
import { copyFileSync, mkdirSync } from "node:fs";

const out = new URL("../nox/.local/lib/nox/notes-app/web/", import.meta.url).pathname;
mkdirSync(out, { recursive: true });

await build({
    entryPoints: { app: "src/main.js" },
    bundle: true,
    format: "iife",
    minify: true,
    target: "chrome130",
    outdir: out,
    loader: { ".woff2": "dataurl", ".woff": "dataurl", ".ttf": "dataurl", ".svg": "text" },
    legalComments: "linked",
    logLevel: "info",
});
copyFileSync("src/index.html", out + "index.html");
