---
name: write-verso-post
description: Write a new Verso blog post for the site. Use when asked to write a blog post, article, reading note, or page. Creates a Lean file with Verso markup and wires it into the site build.
---

# Write a Verso Post

## Steps

1. Create the `.lean` file under `Site/Blog/` (for reading notes, commentary) or `Site/Projects/` (for project write-ups)
2. Add the import to `Site/Main.lean`
3. Add the post to the `personalSite` definition in the appropriate section
4. Run `lake build` to verify it compiles
5. Run `.lake/build/bin/ngrislain-github-io --output build` to generate the site

## Template

```lean
import VersoBlog

open Verso Genre Blog

#doc (Post) "Title Here" =>

%%%
authors := ["Nicolas Grislain"]
date := { year := YYYY, month := MM, day := DD }
%%%

First paragraph here.

# Section heading

More content.
```

## Verso Markup (NOT standard Markdown)

### Emphasis and bold
- Bold: `*text*` (single asterisks). NEVER use `**`.
- Italic/emphasis: `_text_` (underscores)
- Nested emphasis: `__outer _inner_ outer__`

### Math (LaTeX via KaTeX)
- Inline: `` $`\sum_{i=0}^{10} i` ``
- Display: `` $$`\sum_{i=0}^{10} i` ``

### Links and images
- `[text](url)` or `[text][ref]` with `[ref]: url`
- `![alt](path)` or `![alt][ref]`

### Code
- Inline: `` `code` ``
- Block: triple backticks
- Named: `` ```lean `` for Lean highlighting with elaboration
- With args: `` ```lean (error := true) ``

### Lists
- Unordered: `*`, `-`, or `+` at line start
- Ordered: `1.` or `1)` at line start
- Description: `: Term` then blank line then indented description

### Other blocks
- Quotes: `> text`
- Directives: `:::name args` content `:::`
- Roles: `{roleName arg}[content]`

### Headers
- Must be well-nested: first `#`, then `##`, etc. No skipping.
- Metadata after header: `%%% key := value %%%`

### Key differences from Markdown
- `*` is bold, NOT `**`
- `_` is emphasis/italic
- Math uses `` $` `` not `$`
- Headers must be well-nested (no skipping levels)
- Different list indicators or indentation levels create separate lists

## Wiring into Main.lean

Add import:
```lean
import Site.Blog.MyPost  -- or Site.Projects.MyPost
```

Add to personalSite:
```lean
"blog" Site.Blog with
  Site.Blog.MyPost    -- add here
  Site.Blog.PrefixScan
```
