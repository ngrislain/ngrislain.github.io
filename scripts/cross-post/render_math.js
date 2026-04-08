#!/usr/bin/env node
// Reads JSON array of {id, latex, displayMode} on stdin.
// Outputs JSON array of {id, svg} on stdout.
// Each SVG is the KaTeX-rendered equation as a self-contained SVG string.

const katex = require("katex");
const crypto = require("crypto");

let input = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => (input += chunk));
process.stdin.on("end", () => {
  const equations = JSON.parse(input);
  const results = equations.map(({ id, latex, displayMode }) => {
    try {
      const html = katex.renderToString(latex, {
        displayMode: !!displayMode,
        throwOnError: false,
        output: "mathml",
      });
      return { id, html, error: null };
    } catch (e) {
      return { id, html: null, error: e.message };
    }
  });
  process.stdout.write(JSON.stringify(results));
});
