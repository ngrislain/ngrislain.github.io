# ngrislain.github.io

This repository hosts the Lean 4/Verso source for [ngrislain.github.io](https://ngrislain.github.io).

## Local development

Build once and preview:

```bash
lake exe ngrislain-github-io --output build
(cd build && python3 -m http.server)
```

Or let it rebuild itself while you edit:

```bash
./scripts/dev.sh
```

That builds the site, serves `build/` on <http://localhost:8000>, and rebuilds
whenever anything under `Site/` or `static/` changes, or `lakefile.lean` or
`lean-toolchain` does. A successful build prints one line; if it fails you get
the full lake output and the last good copy stays up. Ctrl-C stops the server
and the watcher together.

```bash
PORT=9000 ./scripts/dev.sh      # different port
BIND=0.0.0.0 ./scripts/dev.sh   # reachable from your phone
VERBOSE=1 ./scripts/dev.sh      # show lake output on success too
```

It uses [fswatch](https://github.com/emcrisostomo/fswatch) (`brew install
fswatch`) when it is installed and falls back to polling once a second when it
is not. `watch -g` is not used: it only detects changes while it owns the
terminal, so it would blank the build log for the whole time it is waiting.

`lake update` is deliberately not part of any of this. It refetches
dependencies and rewrites `lake-manifest.json` and `lean-toolchain`, so run it
by hand when you mean to move the toolchain.

The generated static site is written to `build/`.

## Deployment

GitHub Actions build and publish the site automatically on pushes to `main`. The workflow is defined in `.github/workflows/deploy.yml` and performs the following steps:

1. Install the Lean toolchain specified in `lean-toolchain`
2. Run `lake update` to fetch dependencies
3. Build the Verso site into `build/`
4. Upload the result to GitHub Pages (`gh-pages` environment)

You can also trigger the workflow manually from the Actions tab.