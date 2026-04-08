# AGENTS.md

## Git

- Never commit automatically. Always ask the user before committing.
- Never push automatically. Always ask the user before pushing.

## Writing style

When writing prose for blog posts or any user-facing text, write like a real person. Avoid patterns that signal AI-generated content:

- No em dashes. Use commas, periods, or parentheses instead.
- No "delve", "leverage", "comprehensive", "crucial", "innovative", "cutting-edge", "game-changing", "paradigm", "synergy", "aforementioned", "moreover", "furthermore", "in conclusion".
- No filler transitions like "It's worth noting that", "Interestingly", "It's important to understand that".
- No excessive hedging: "It could potentially be argued that" or "This might suggest that perhaps".
- No bullet point walls when a paragraph would be more natural.
- No repetitive sentence structures. Vary rhythm and length.
- No emoji unless the user explicitly asks for them.
- Write short, direct sentences. Say what you mean. If a sentence does not add information, cut it.
- The author is a non-native English speaker. Use natural vocabulary, not rare or fancy words.

## Skills

Skills are located in `.skills/` following the [Agent Skills](https://agentskills.io) specification.

- [write-verso-post](.skills/write-verso-post/SKILL.md) — Write a Verso blog post (`.lean` file with markup, wired into site build)
- [write-interactive-html](.skills/write-interactive-html/SKILL.md) — Write a self-contained interactive HTML page with inline CSS/JS

## Project overview

Personal website of Nicolas Grislain, built with [Verso](https://github.com/leanprover/verso) — a static site generator written in Lean 4. Verso uses a Markdown-like markup language embedded in Lean files, compiled to HTML. The site compiles `.lean` source files into static pages.

## Build

```bash
lake build                                    # compile everything
.lake/build/bin/ngrislain-github-io --output build  # generate site into build/
```

The executable generates HTML pages AND an RSS feed (`build/feed.xml`).

## Project structure

```
lakefile.lean              # Lake build config, depends on verso
Site/
  Main.lean                # Site definition + RSS feed generation
  Theme.lean               # PaperMod-inspired theme (templates, CSS/JS injection)
  Front.lean               # Homepage
  About.lean               # About page
  Blog.lean                # Blog section landing page
  Blog/
    PrefixScan.lean        # Reading note post
  Projects.lean            # Projects section landing page
  Projects/
    TypeDrivenDev.lean      # "Don't Vibe — Prove" post
    AIEconomics.lean        # "How to Die Optimally" post (links to interactive HTML)
    Adventure.lean          # Pyxel 3D geometry post
static/
  chalk.css                # Theme stylesheet
  favicon.svg
  projects/
    ai-economics/
      ai-economics.html    # Interactive paper (HTML + inline CSS + D3.js + KaTeX)
    adventure/
      adventure.html        # Interactive Pyxel project page
```

## Adding content

### New Verso post

1. Create `Site/Blog/MyPost.lean` or `Site/Projects/MyPost.lean`
2. Use this template:
```lean
import VersoBlog

open Verso Genre Blog

#doc (Post) "Post Title" =>

%%%
authors := ["Nicolas Grislain"]
date := { year := 2026, month := 03, day := 13 }
%%%

Content goes here.
```
3. Add `import Site.Blog.MyPost` (or `Site.Projects.MyPost`) to `Site/Main.lean`
4. Add the post to the `personalSite` definition

### Interactive HTML page

Interactive content lives as standalone HTML files in `static/projects/<name>/`. These are self-contained with inline CSS and JS (no external dependencies beyond CDNs). They are linked from Verso posts.

## Verso markup reference

Verso markup is Markdown-like but NOT identical to Markdown. Key differences below.

### Emphasis and bold

- Emphasis (italic): `_text_` (underscores, NOT asterisks)
- Bold: `*text*` (single asterisks)
- NEVER use `**` — it does not exist in Verso
- Nested emphasis: `__outer _inner_ outer__`

### Headings

Headers use `#` like Markdown. The first header MUST use a single `#`. Subsequent headers may have at most one more `#` than the preceding header (well-nesting required).

```
# Top level
## Sub section
### Sub-sub section
```

Metadata blocks follow headers with `%%%`:
```
# My Section
%%%
tag := "my-tag"
%%%
```

### Links and images

```
[Link text](https://example.com)
[Named link][ref]
[ref]: https://example.com

![Alt text](image.png)
![Alt text][ref]
```

### Math (LaTeX via KaTeX)

- Inline: `` $`\sum_{i=0}^{10} i` ``
- Display: `` $$`\sum_{i=0}^{10} i` ``

### Code

- Inline: `` `code` ``
- Block: triple backticks (standard)
- Named code blocks: `` ```lean `` triggers Lean-specific highlighting/elaboration
- Code blocks with args: `` ```lean (error := true) ``

### Lists

- Unordered: `*`, `-`, or `+` at start of line
- Ordered: `1.` or `1)` at start of line
- Description lists:
  ```
  : Term

    Description of the term
  ```
- List items with same indicator and indentation form one list
- Different indicators or indentation = different lists

### Block quotes

```
> Quoted text

  Continues here (indented past >)
```

### Directives (custom blocks)

```
:::directiveName arg1 arg2
  Content inside the directive
:::
```

Nested directives use more colons for the outer one:
```
::::outer
:::inner
Content
:::
::::
```

### Roles (inline extensions)

Roles apply special meaning to inline content:
```
{roleName arg}[inline content]
```

### Blog-specific

- `#doc (Post) "Title" =>` starts a blog post
- `#doc (Page) "Title" =>` starts a page (non-post)
- Metadata block after header: `%%% ... %%%`
- Post metadata: `authors`, `date`, `categories`

## Lean conventions

- Lean keyword conflicts: avoid `section`, `exists`, `where`, `do`, `if`, `for` as variable names in site code
- `String.drop`/`String.take` return `String.Slice` — call `.toString` to convert back
- `String.trim` is deprecated — use `String.trimAscii.toString`
- The RSS feed is generated in Lean in `Site/Main.lean`, not via external scripts
- Share buttons (LinkedIn, Bluesky, Threads, X, HN, Reddit, Lobsters, Email) are injected via JS in the post template
