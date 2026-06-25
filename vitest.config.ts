import { defineConfig } from "vitest/config";

// The api/ source uses ESM-style ".js" extensions on its relative imports
// (e.g. import … from "../_lib/strava.js") while the files are TypeScript.
// This pre-resolve plugin rewrites a relative ".js" specifier to ".ts" so
// Vitest/Vite can load the actual source under test.
export default defineConfig({
  plugins: [
    {
      name: "resolve-js-to-ts",
      enforce: "pre",
      async resolveId(source, importer) {
        if (importer && (source.startsWith("./") || source.startsWith("../")) && source.endsWith(".js")) {
          const asTs = source.slice(0, -3) + ".ts";
          const resolved = await this.resolve(asTs, importer, { skipSelf: true });
          if (resolved) return resolved.id;
        }
        return null;
      },
    },
  ],
  test: {
    environment: "node",
    include: ["test/**/*.test.ts"],
  },
});
