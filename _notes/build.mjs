// Bundles src/ into ../nox/.local/lib/nox/notes-app/web (one IIFE script + one stylesheet: WebKit
// loads them from file://, where ES modules are blocked). The output is committed, so the app runs
// without node; rebuild after changing src/ or bumping @milkdown/crepe:  npm ci && npm run build
import { build } from "esbuild";
import { copyFileSync, mkdirSync } from "node:fs";

const out = new URL("../nox/.local/lib/nox/notes-app/web/", import.meta.url).pathname;
mkdirSync(out, { recursive: true });

await build({
    entryPoints: { app: "src/main.js" },
    bundle: true,
    format: "iife",
    minify: true,
    target: "safari16",          // WebKitGTK 2.4x
    outdir: out,
    loader: { ".woff2": "dataurl", ".woff": "dataurl", ".ttf": "dataurl", ".svg": "text" },
    external: ["grain.png"],
    legalComments: "linked",
    logLevel: "info",
});
copyFileSync("src/index.html", out + "index.html");
copyFileSync("../quickshell/.config/quickshell/nox/assets/grain.png", out + "grain.png");
