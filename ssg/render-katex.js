#!/usr/bin/env node
const fs = require("fs");
const path = require("path");
const katex = require("../assets/katex.min.js");

const ROOT = process.argv[2] || "zig-out/.zine-release-raw";
const RELEASE = process.argv.includes("--release");
const MATH_SCRIPT_RE = /<script\b([^>]*)\btype=(["'])math\/tex\2([^>]*)>([\s\S]*?)<\/script>/gi;
const FRONTEND_SCRIPT_RE = /<script\b[^>]*\bsrc=(["'])\/?(?:katex\.min|render-katex)\.js\1[^>]*><\/script>\s*/gi;

function walk(dir) {
  for (const name of fs.readdirSync(dir)) {
    const file = path.join(dir, name);
    const stat = fs.statSync(file);
    if (stat.isDirectory()) {
      walk(file);
    } else if (file.endsWith(".html")) {
      renderFile(file);
    }
  }
}

function renderFile(file) {
  const html = fs.readFileSync(file, "utf8");
  let rendered = html.replace(MATH_SCRIPT_RE, (_match, _before, _quote, _after, tex, offset) => {
    return katex.renderToString(tex, {
      displayMode: !insideParagraph(html, offset),
      throwOnError: false,
      strict: false,
    });
  });
  if (RELEASE) rendered = rendered.replace(FRONTEND_SCRIPT_RE, "");

  if (rendered !== html) fs.writeFileSync(file, rendered);
}

function insideParagraph(html, offset) {
  let open = false;
  for (const tag of html.slice(0, offset).matchAll(/<\/?p(?=[\s>/])/gi)) {
    open = tag[0][1] !== "/";
  }
  return open;
}

walk(ROOT);
if (RELEASE) {
  fs.rmSync(path.join(ROOT, "katex.min.js"), { force: true });
  fs.rmSync(path.join(ROOT, "render-katex.js"), { force: true });
}

