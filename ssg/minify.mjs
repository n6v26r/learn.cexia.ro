#!/usr/bin/env node

import { minify as minifyHtml } from "html-minifier-terser";
import { transform as minifyCss, transformStyleAttribute } from "lightningcss";
import { minify as minifyJs } from "terser";
import { readdir, readFile, stat, writeFile } from "node:fs/promises";
import path from "node:path";

const root = process.argv[2] ?? "zig-out/release";
const minifiable = new Set([".html", ".css", ".js", ".json", ".webmanifest"]);

async function* walk(dir) {
  for (const name of await readdir(dir)) {
    const file = path.join(dir, name);
    const info = await stat(file);

    if (info.isDirectory()) {
      yield* walk(file);
    } else if (info.isFile() && minifiable.has(path.extname(file).toLowerCase())) {
      yield file;
    }
  }
}

async function minifyJsText(source) {
  const result = await minifyJs(source, {
    ecma: 2022,
    compress: true,
    mangle: true,
    format: {
      comments: false,
    },
  });

  if (typeof result.code !== "string") {
    throw new Error("terser produced no output");
  }

  return result.code;
}

function minifyCssText(source, filename) {
  return minifyCss({
    filename,
    code: Buffer.from(source),
    minify: true,
  }).code.toString();
}

function minifyCssAttribute(source, filename) {
  return transformStyleAttribute({
    filename,
    code: Buffer.from(source),
    minify: true,
  }).code.toString();
}

async function minifyHtmlText(source, filename) {
  return await minifyHtml(source, {
    collapseBooleanAttributes: true,
    collapseWhitespace: true,
    keepClosingSlash: true,
    minifyCSS: (css, type) =>
      type === "inline"
        ? minifyCssAttribute(css, `${filename}.inline-style.css`)
        : minifyCssText(css, `${filename}.inline.css`),
    minifyJS: (js) => minifyJsText(js),
    removeAttributeQuotes: false,
    removeComments: true,
    removeOptionalTags: false,
    removeRedundantAttributes: false,
    removeScriptTypeAttributes: true,
    removeStyleLinkTypeAttributes: true,
  });
}

async function minifyFile(file) {
  const before = await readFile(file, "utf8");
  const ext = path.extname(file).toLowerCase();

  let after;
  if (ext === ".html") {
    after = await minifyHtmlText(before, file);
  } else if (ext === ".css") {
    after = minifyCssText(before, file);
  } else if (ext === ".js") {
    after = await minifyJsText(before);
  } else {
    after = JSON.stringify(JSON.parse(before));
  }

  if (after !== before) {
    await writeFile(file, after, "utf8");
    return true;
  }

  return false;
}

let changed = 0;
for await (const file of walk(root)) {
  changed += Number(await minifyFile(file));
}

console.log(`minified ${changed} files in ${root}`);

