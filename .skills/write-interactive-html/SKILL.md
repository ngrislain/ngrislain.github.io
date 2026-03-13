---
name: write-interactive-html
description: Write a self-contained interactive HTML page with inline CSS and JS for embedding as a static asset on the site. Use when asked to create interactive visualizations, papers, apps, or demos.
---

# Write an Interactive HTML Page

## Steps

1. Create the HTML file at `static/projects/<name>/<name>.html`
2. The file must be self-contained: inline `<style>` and `<script>` tags
3. External CDN dependencies are acceptable (D3.js, KaTeX, Three.js, etc.)
4. Create or update the corresponding Verso post in `Site/Projects/` that links to it
5. Link pattern in Verso post: `[Link text](static/projects/<name>/<name>.html)`

## Reference implementation

See `static/projects/ai-economics/ai-economics.html` for the canonical example. It uses:
- `latex.vercel.app` CSS for academic paper styling
- KaTeX for mathematical rendering
- D3.js for interactive charts and visualizations
- A fixed left panel for parameter controls
- Responsive design with media queries

## Conventions

- Academic/research content: use paper-like styling (serif fonts, narrow column, numbered sections)
- Interactive controls: fixed sidebar panel or inline sliders/inputs
- Mathematical rendering: KaTeX (loaded from CDN)
- Charts/visualizations: D3.js (loaded from CDN)
- 3D graphics: Three.js (loaded from CDN)
- Games/pixel art: Pyxel or Canvas API
- Always include responsive design with `@media` queries
- Include a descriptive `<title>` tag
- Use `<meta charset="utf-8">` and viewport meta tag

## HTML skeleton

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Page Title</title>
  <style>
    /* All CSS inline */
  </style>
</head>
<body>
  <!-- Content -->
  <script>
    // All JS inline
  </script>
</body>
</html>
```

## Linking from Verso post

In the corresponding `Site/Projects/MyProject.lean`:
```
The interactive version is here: [Title](static/projects/my-project/my-project.html).
```
