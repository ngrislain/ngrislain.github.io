# ngrislain.github.io

This repository hosts the Lean 4/Verso source for [ngrislain.github.io](https://ngrislain.github.io).

## Local development

```bash
lake update
lake exe ngrislain-github-io --output build
```

The generated static site is written to the `build/` directory. Open `build/index.html` in a browser to preview the site locally.

## Deployment

GitHub Actions build and publish the site automatically on pushes to `main`. The workflow is defined in `.github/workflows/deploy.yml` and performs the following steps:

1. Install the Lean toolchain specified in `lean-toolchain`
2. Run `lake update` to fetch dependencies
3. Build the Verso site into `build/`
4. Upload the result to GitHub Pages (`gh-pages` environment)

You can also trigger the workflow manually from the Actions tab.