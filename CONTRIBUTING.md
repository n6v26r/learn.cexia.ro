# Contributing

Contributions to the lessons, design, and site generator are welcome.

## Set up the project

The supported build environment is Linux x86-64 with internet access and the
Zig version pinned in `build.zig.zon`. [AnyZig](https://marler8997.github.io/anyzig/)
can obtain that compiler automatically.

```sh
git clone <repository-url>
cd learn.cexia.ro
zig build
zig build test
zig build serve # for dev server
```

The development server is available at <http://localhost:1991>. Changes to
files or directories under `site/` regenerate the intermediate Zine content;
changes to layouts and assets are handled by Zine directly.

No system Node.js or Python installation is required. The build obtains pinned
copies of its tools and dependencies. See [README.md](README.md) for the exact
compiler and platform requirements.

## Add a lesson

Lesson sources belong in `site/`. Keep filenames ordered and URL-safe because
the directory hierarchy determines both URLs and navigation.

### Notebook lesson

Add the notebook and, when metadata is needed, a same-name sidecar:

```text
site/python/01-example.ipynb
site/python/01-example.smd
```

The sidecar may contain frontmatter followed by introductory SuperMD content.
That content is rendered before the notebook cells. If `.title` is omitted, the
generator uses the first Markdown heading in the notebook, then falls back to
the filename.

### Standalone lesson

An `.smd` file without a same-name notebook becomes a complete lesson:

```text
site/python/02-text-lesson.smd
```

Its frontmatter is followed by the lesson body.
### Directory page

Add `index.smd` inside a directory to define its landing page:

```text
site/python/index.smd
site/python/algoritmica/index.smd
```

`site/index.smd` defines the homepage. Its `ftree` content section marks where
the module cards are rendered. If abset, the file-tree is rendered at the end of the page.

## Frontmatter

A typical lesson sidecar or standalone document begins with:

```zig
---
.title = "01 · Example lesson",
.description = "A concise summary shown in lesson listings.",
.authors = ["cexia-learn"],
.tags = ["python", "fundamente"],
.custom = .{
    .level = "Începător",
    .duration = "45 min",
},
---
```

Supported page metadata includes `title`, `description`, `authors`, `tags`,
`date`, `layout`, `aliases`, and `custom`. Common lesson-specific values under
`custom` are `level`, `duration`, `cpu`, `memory`, `gpu`, and `problem_url`.
Notebook Python version and execution time are derived automatically when the
source notebook provides them.

Tags and authors use stable identifiers in frontmatter. Add their displayed
names to `assets/tags.json` and `assets/authors.json`. Unknown identifiers do
not receive a human-readable label on the filtering page.

Breadcrumbs and default layouts are generated from the project structure. Only
set `layout` for a genuinely custom page such as a special page.

## Validate a change

Run all local checks before opening a pull request:

```sh
zig build
zig build test
zig build release
```

- `zig build` writes the development site to `zig-out/dist`.
- `zig build test` exercises the source-tree hashing used by the watcher.
- `zig build release` writes the optimized deployment to `zig-out/release`.

Keep generator changes small. Prefer templates, CSS, or focused browser scripts
when the requested behavior does not require Zig. Do not commit downloaded
dependencies, generated fonts, caches, notebook checkpoints, or `zig-out/`.

## Deployment

Auto deployment in not set up yet.
