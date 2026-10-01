#!/bin/sh

set -eu

zig build release
git push
vercel deploy --cwd zig-out/release --prod --project learn.cexia.ro
