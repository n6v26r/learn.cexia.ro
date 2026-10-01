> [!NOTE]
> This code was written with LLM assistance.

# CEXIA Learn

The source of [learn.cexia.ro](https://learn.cexia.ro), a static Romanian-language
library of AI lessons written as Jupyter notebooks and SuperMD documents.

[Zine](https://zine-ssg.io/) renders the site. A small Zig middleware converts
the lesson sources into Zine content, builds the navigation hierarchy, and
extracts notebook cells and outputs.

## Requirements

The build is hermetic: it does not use a system installation of Node.js, Python,
npm, pip, or any font tooling. Zig downloads every pinned build dependency from
`build.zig.zon`; the release pipeline installs its locked JavaScript and Python
packages inside `zig-out/`.

You need:

- internet access;
- the Zig version pinned by `build.zig.zon`;
- Linux x86-64, currently required by the pinned release toolchain.

[AnyZig](https://marler8997.github.io/anyzig/) is the simplest way to obtain the
compiler. It reads `.mach_zig_version` and downloads `2026.6.18-mach`
automatically. A manual installation must provide Zig
`0.17.0-dev.892+54537285c`. Windows is not tested; use WSL with an x86-64 Linux
environment.

## Development

Build the development site and run its tests:

```sh
zig build
zig build test
```

Start the development server at <http://localhost:1991>:

```sh
zig build serve
```

Zine watches layouts and assets. The Zig supervisor additionally hashes the
names, types, and contents of entries under `site/`, regenerates the middleware
output when that tree changes, and lets Zine reload the browser. A failed content
generation keeps the last valid site available.

The host and port can be changed when necessary:

```sh
zig build serve -Dserve-host=0.0.0.0 -Dserve-port=8080
```

Build the minified, cache-busted site with:

```sh
zig build release
```

Development output is written to `zig-out/dist`; release output is written to
`zig-out/release`.

## Content

All source content lives in `site/`. A lesson can be either:

- an `.ipynb` notebook with an optional same-name `.smd` metadata sidecar; or
- a standalone `.smd` lesson.

`index.smd` defines the landing page for its directory. The directory hierarchy
becomes both the URL hierarchy and the navigation tree; pages in each directory
are listed by ascending frontmatter `date` rank.
See [CONTRIBUTING.md](CONTRIBUTING.md) for the content formats, metadata fields,
and validation workflow.

## Project structure

```text
assets/       styles, browser scripts, static files, and generated font assets
build/        lesson conversion, file watching, and build orchestration
layouts/      Zine/SuperHTML page templates
site/         lesson sources, directory metadata, and special pages
ssg/          release-only rendering and optimization helpers
```

Build dependencies are declared in `build.zig.zon`. JavaScript and Python
dependency versions are locked as well. Downloaded dependencies, materialized
assets, caches, and generated output are intentionally untracked.

## License

The project is available under your choice of the
[Zero-Clause BSD license or The Unlicense](LICENSE).
