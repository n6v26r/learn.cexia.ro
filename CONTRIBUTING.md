# Contributing

Contributions to the lessons, design, and site generator are welcome.

For toolchain setup, building, testing, the development server, and release
checks, follow the [README](README.md#requirements).

## Add a lesson

Lesson sources belong in `site/`. Keep filenames URL-safe because the directory
hierarchy determines both URLs and navigation.

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

Read the [SuperMD documentation](https://zine-ssg.io/docs/supermd/) before
authoring content that uses sections, blocks, assets, or other directives. The
[SuperMD Scripty reference](https://zine-ssg.io/docs/supermd/scripty/) lists the
directives available inside expressions such as `[]($section.id('intro'))`.

### Directory page

Add `index.smd` inside a directory to define its landing page:

```text
site/python/index.smd
site/python/algoritmica/index.smd
```

Every directory page must contain `[]($section.id('ftree'))` where its child
cards should be rendered.

## Frontmatter

A typical lesson sidecar or standalone document begins with:

```zig
---
.title = "01 · Example lesson",
.description = "A concise summary shown in lesson listings.",
.date = .unix(0),
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
`custom` are `level`, `duration`, `cpu`, `memory`, and `gpu`.
Notebook Python version and execution time are derived automatically when the
source notebook provides them.

Navigation and directory listings order pages by date, with smaller values
first. Set `.date = .unix(number)` on both lessons and directory `index.smd`
pages; the number acts as their rank among siblings. Pages with the same or no
value are ordered by their URL, so use distinct values whenever their relative
position matters. There is no separate `.order` field.

Tags and authors use stable identifiers in frontmatter. Add their displayed
names to `assets/tags.json` and `assets/authors.json`. Unknown identifiers do
not receive a human-readable label on the filtering page.

Breadcrumbs and default layouts are generated from the project structure. Only
set `layout` for a genuinely custom page such as a special page.

## Content license

Original lesson text, examples, notebook content, and lesson metadata are
dedicated to the public domain under [CC0 1.0 Universal](LICENSE-CONTENT).
Contributors must only submit material for which they have the necessary rights.

The dedication does not cover third-party fonts, libraries, images, logos,
trademarks, personal data, or other externally licensed material. See
[LICENSE-CONTENT](LICENSE-CONTENT) for the complete scope and exclusions.

## Code changes

Keep generator changes small. Prefer templates, CSS, or focused browser scripts
when the requested behavior does not require Zig.
