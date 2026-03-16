import VersoBlog

open Verso
open Genre Blog
open Output Html
open Template
open Verso.Genre.Blog Theme

namespace Site

open Verso.Genre.Blog

private def siteTitle : String := "NGrislain"

private def monthName : Nat → String
  | 1 => "January"
  | 2 => "February"
  | 3 => "March"
  | 4 => "April"
  | 5 => "May"
  | 6 => "June"
  | 7 => "July"
  | 8 => "August"
  | 9 => "September"
  | 10 => "October"
  | 11 => "November"
  | 12 => "December"
  | n => toString n

private def formatDate (date : Verso.Genre.Blog.Date) : String :=
  s!"{monthName date.month} {date.day}, {date.year}"

private def renderCategoryLinks (catAddr : String → String) (cats : List Post.Category) : Html :=
  if cats.isEmpty then
    Html.empty
  else
    {{
      <span class="post-tags-inline">
        {{ cats.toArray.map (fun cat => {{<a href={{catAddr cat.slug}}>{{cat.name}}</a>}}) }}
      </span>
    }}

private def renderMetadataFooter (catAddr : String → String) (date : Verso.Genre.Blog.Date) (cats : List Post.Category) : Html :=
  let catLinks := renderCategoryLinks catAddr cats
  {{
    <div class="post-meta">
      <span>{{formatDate date}}</span>
      {{ if cats.isEmpty then Html.empty else {{<span>" · "</span>}} }}
      {{ if cats.isEmpty then Html.empty else catLinks }}
    </div>
  }}

private def themeToggleScript : String :=
  "
  (function() {
    var theme = localStorage.getItem('pref-theme');
    if (theme === 'dark') {
      document.documentElement.setAttribute('data-theme', 'dark');
    } else if (theme === 'light') {
      document.documentElement.setAttribute('data-theme', 'light');
    } else if (window.matchMedia('(prefers-color-scheme: dark)').matches) {
      document.documentElement.setAttribute('data-theme', 'dark');
    }
  })();
  "

private def shareScript : String :=
  "
  document.addEventListener('DOMContentLoaded', function() {
    var el = document.getElementById('share-buttons');
    if (!el) return;
    var rawUrl = window.location.href;
    var url = encodeURIComponent(rawUrl);
    var rawTitle = document.title.split(' | ')[0];
    var title = encodeURIComponent(rawTitle);
    var msg = encodeURIComponent(rawTitle + ' ' + rawUrl);
    var icons = {
      linkedin: 'M20.447 20.452h-3.554v-5.569c0-1.328-.027-3.037-1.852-3.037-1.853 0-2.136 1.445-2.136 2.939v5.667H9.351V9h3.414v1.561h.046c.477-.9 1.637-1.85 3.37-1.85 3.601 0 4.267 2.37 4.267 5.455v6.286zM5.337 7.433a2.062 2.062 0 01-2.063-2.065 2.064 2.064 0 112.063 2.065zm1.782 13.019H3.555V9h3.564v11.452zM22.225 0H1.771C.792 0 0 .774 0 1.729v20.542C0 23.227.792 24 1.771 24h20.451C23.2 24 24 23.227 24 22.271V1.729C24 .774 23.2 0 22.222 0h.003z',
      bluesky: 'M12 10.8c-1.087-2.114-4.046-6.053-6.798-7.995C2.566.944 1.561 1.266.902 1.565.139 1.908 0 3.08 0 3.768c0 .69.378 5.65.624 6.479.785 2.627 3.584 3.493 6.173 3.063-4.626.786-8.664 3.844-4.233 8.538C6.534 26.108 8.91 20.234 12 16.842c3.09 3.392 5.466 9.266 9.436 5.006 4.43-4.694.393-7.752-4.233-8.538 2.59.43 5.39-.436 6.174-3.063.245-.829.623-5.79.623-6.479 0-.688-.139-1.86-.902-2.203-.659-.3-1.664-.62-4.3 1.24C16.046 4.748 13.087 8.687 12 10.8',
      threads: 'M16.5 8.5c-1.2-1.2-2.8-1.8-4.5-1.8s-3.3.6-4.5 1.8C6.3 9.7 5.7 11.3 5.7 13s.6 3.3 1.8 4.5c1.2 1.2 2.8 1.8 4.5 1.8s3.3-.6 4.5-1.8c1.2-1.2 1.8-2.8 1.8-4.5s-.6-3.3-1.8-4.5zm-1.4 7.6c-.8.8-1.9 1.3-3.1 1.3s-2.3-.5-3.1-1.3C8 15.3 7.5 14.2 7.5 13s.5-2.3 1.4-3.1c.8-.8 1.9-1.3 3.1-1.3s2.3.5 3.1 1.3c.8.8 1.3 1.9 1.3 3.1s-.5 2.3-1.3 3.1zM12 0C5.4 0 0 5.4 0 12s5.4 12 12 12 12-5.4 12-12S18.6 0 12 0zm0 22C6.5 22 2 17.5 2 12S6.5 2 12 2s10 4.5 10 10-4.5 10-10 10zm1.2-11.5c-.1-.7-.5-1.2-1.2-1.2s-1.2.5-1.2 1.2v2.8c0 .7.5 1.2 1.2 1.2s1.1-.4 1.2-1l1.6.3c-.2 1.3-1.4 2.3-2.8 2.3-1.6 0-2.8-1.3-2.8-2.8v-2.8c0-1.6 1.3-2.8 2.8-2.8 1.4 0 2.6 1 2.8 2.3l-1.6.5z',
      x: 'M18.901 1.153h3.68l-8.04 9.19L24 22.846h-7.406l-5.8-7.584-6.638 7.584H.474l8.6-9.83L0 1.154h7.594l5.243 6.932ZM17.61 20.644h2.039L6.486 3.24H4.298Z',
      ycombinator: 'M0 24V0h24v24H0zM6.951 5.896l4.112 7.708v5.064h1.583v-4.972l4.148-7.799h-1.749l-2.457 4.875c-.372.745-.688 1.434-.688 1.434s-.297-.708-.651-1.434L8.831 5.896h-1.88z',
      reddit: 'M12 0A12 12 0 0 0 0 12a12 12 0 0 0 12 12 12 12 0 0 0 12-12A12 12 0 0 0 12 0zm5.01 4.744c.688 0 1.25.561 1.25 1.249a1.25 1.25 0 0 1-2.498.056l-2.597-.547-.8 3.747c1.824.07 3.48.632 4.674 1.488.308-.309.73-.491 1.207-.491.968 0 1.754.786 1.754 1.754 0 .716-.435 1.333-1.01 1.614a3.111 3.111 0 0 1 .042.52c0 2.694-3.13 4.87-7.004 4.87-3.874 0-7.004-2.176-7.004-4.87 0-.183.015-.366.043-.534A1.748 1.748 0 0 1 4.028 12c0-.968.786-1.754 1.754-1.754.463 0 .898.196 1.207.49 1.207-.883 2.878-1.43 4.744-1.487l.885-4.182a.342.342 0 0 1 .14-.197.35.35 0 0 1 .238-.042l2.906.617a1.214 1.214 0 0 1 1.108-.701zM9.25 12C8.561 12 8 12.562 8 13.25c0 .687.561 1.248 1.25 1.248.687 0 1.248-.561 1.248-1.249 0-.688-.561-1.249-1.249-1.249zm5.5 0c-.687 0-1.248.561-1.248 1.25 0 .687.561 1.248 1.249 1.248.688 0 1.249-.561 1.249-1.249 0-.687-.562-1.249-1.25-1.249zm-5.466 3.99a.327.327 0 0 0-.231.094.33.33 0 0 0 0 .463c.842.842 2.484.913 2.961.913.477 0 2.105-.056 2.961-.913a.361.361 0 0 0 .029-.463.33.33 0 0 0-.464 0c-.547.533-1.684.73-2.512.73-.828 0-1.979-.196-2.512-.73a.326.326 0 0 0-.232-.095z',
      lobsters: 'M16.496 15.616c.096-.32.16-.656.16-1.008V9.2c0-1.856-1.344-3.2-3.2-3.2H7.2C5.344 6 4 7.344 4 9.2v5.408c0 1.856 1.344 3.2 3.2 3.2h4.48l3.584 2.528v-3.776l1.232-.944zm-3.04-1.008c0 .64-.384 1.024-1.024 1.024H8.224c-.64 0-1.024-.384-1.024-1.024V9.2c0-.64.384-1.024 1.024-1.024h4.208c.64 0 1.024.384 1.024 1.024v5.408zM20 3.2v5.408c0 1.856-1.344 3.2-3.2 3.2h-.608V9.2c0-2.496-1.904-4.4-4.4-4.4H8.608c.32-1.024 1.248-1.6 2.192-1.6h5.408c1.856 0 3.792 1.344 3.792 3.2v-3.2z',
      email: 'M20 4H4c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2zm0 4l-8 5-8-5V6l8 5 8-5v2z'
    };
    var links = [
      ['https://www.linkedin.com/sharing/share-offsite/?url=' + url, 'LinkedIn', 'linkedin'],
      ['https://bsky.app/intent/compose?text=' + msg, 'Bluesky', 'bluesky'],
      ['https://www.threads.net/intent/post?text=' + msg, 'Threads', 'threads'],
      ['https://x.com/intent/tweet?url=' + url + '&text=' + title, 'X', 'x'],
      ['https://news.ycombinator.com/submitlink?u=' + url + '&t=' + title, 'Hacker News', 'ycombinator'],
      ['https://www.reddit.com/submit?url=' + url + '&title=' + title, 'Reddit', 'reddit'],
      ['https://lobste.rs/stories/new?url=' + url + '&title=' + title, 'Lobsters', 'lobsters'],
      ['mailto:?subject=' + title + '&body=' + msg, 'Email', 'email']
    ];
    links.forEach(function(l) {
      var a = document.createElement('a');
      a.href = l[0];
      a.target = '_blank';
      a.rel = 'noopener';
      a.title = l[1];
      var svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
      svg.setAttribute('viewBox', '0 0 24 24');
      svg.setAttribute('width', '18');
      svg.setAttribute('height', '18');
      svg.setAttribute('class', 'share-icon');
      var path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
      path.setAttribute('fill', 'currentColor');
      path.setAttribute('d', icons[l[2]]);
      svg.appendChild(path);
      a.appendChild(svg);
      el.appendChild(a);
    });
  });
  "

private def highlightInitScript : String :=
  "
  document.querySelectorAll('pre').forEach(function(pre) {
    if (!pre.querySelector('.hl') && !pre.classList.contains('hl')) {
      pre.classList.add('language-lean');
      hljs.highlightElement(pre);
    }
  });
  "

private def themeToggleClickScript : String :=
  "
  document.getElementById('theme-toggle').addEventListener('click', function() {
    var current = document.documentElement.getAttribute('data-theme');
    var next = (current === 'dark') ? 'light' : 'dark';
    document.documentElement.setAttribute('data-theme', next);
    localStorage.setItem('pref-theme', next);
  });
  "

private def navigation : Template := do
  pure {{
    <header class="header">
      <nav class="nav">
        <div class="logo">
          <a href="." class="site-title">{{siteTitle}}</a>
        </div>
        <ul class="nav-links">
          {{ ← Theme.dirLinks (← read).site }}
          <li>
            <a href="feed.xml" title="RSS Feed" class="rss-link">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18" class="nav-icon">
                <path fill="currentColor" d="M19.199 24C19.199 13.467 10.533 4.8 0 4.8V0c13.165 0 24 10.835 24 24h-4.801zM3.291 17.415a3.3 3.3 0 0 1 3.293 3.295A3.303 3.303 0 0 1 3.283 24C1.47 24 0 22.526 0 20.71a3.286 3.286 0 0 1 3.291-3.295zM15.909 24h-4.665c0-6.169-5.075-11.245-11.244-11.245V8.09c8.727 0 15.909 7.184 15.909 15.91z"/>
              </svg>
            </a>
          </li>
          <li class="logo-switches">
            <button id="theme-toggle" title="Toggle dark mode">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18" class="nav-icon">
                <path fill="currentColor" d="M12 18a6 6 0 1 1 0-12 6 6 0 0 1 0 12zm0-2a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM11 1h2v3h-2V1zm0 19h2v3h-2v-3zM3.515 4.929l1.414-1.414L7.05 5.636 5.636 7.05 3.515 4.93zM16.95 18.364l1.414-1.414 2.121 2.121-1.414 1.414-2.121-2.121zm2.121-14.85l1.414 1.415-2.121 2.121-1.414-1.414 2.121-2.121zM5.636 16.95l1.414 1.414-2.121 2.121-1.414-1.414 2.121-2.121zM23 11v2h-3v-2h3zM4 11v2H1v-2h3z"/>
              </svg>
            </button>
          </li>
        </ul>
      </nav>
    </header>
  }}

private def footer : Html :=
  {{
    <footer class="footer">
      <span>"This site is generated by "</span>
      <a href="https://github.com/leanprover/verso">"Verso"</a>
      <span>"."</span>
    </footer>
  }}

private def primary : Template := do
  let postsHtml :=
    match (← param? (α := Html) "posts") with
    | none => Html.empty
    | some html => html
  let categoryDirectory :=
    match (← param? (α := Post.Categories) "categories") with
    | none => Html.empty
    | some ⟨cats⟩ => {{
        <div class="tags-page">
          <ul class="tags-list">
            {{ cats.map fun (target, cat) => {{<li><a href={{target}}>{{cat.name}}</a></li>}} }}
          </ul>
        </div>
      }}
  return {{
    <html>
      <head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1"/>
        <meta http-equiv="x-ua-compatible" content="ie=edge"/>
        <title>{{← param (α := String) "title"}}" | "{{siteTitle}}</title>
        <meta property="og:title" content={{← param (α := String) "title"}}/>
        <meta property="og:site_name" content={{siteTitle}}/>
        <meta property="og:type" content="article"/>
        <meta name="twitter:card" content="summary_large_image"/>
        <meta name="twitter:title" content={{← param (α := String) "title"}}/>
        <script>{{themeToggleScript}}</script>
        {{← builtinHeader}}
        <link rel="icon" type="image/svg+xml" href="static/favicon.svg"/>
        <link rel="alternate" type="application/rss+xml" title={{siteTitle}} href="feed.xml"/>
        <link rel="stylesheet" href="static/chalk.css" type="text/css"/>
        <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/default.min.css"/>
        <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
        <script src="https://unpkg.com/highlightjs-lean@1.2.0/dist/lean.min.js"></script>
      </head>
      <body>
        {{← navigation}}
        <main class="main">
          {{← param "content"}}
          {{postsHtml}}
          {{categoryDirectory}}
        </main>
        {{footer}}
        <script>{{themeToggleClickScript}}</script>
        <script>{{highlightInitScript}}</script>
      </body>
    </html>
  }}

private def page : Template := do
  pure {{
    <article>
      <header class="post-header">
        <h1 class="post-title">{{← param "title"}}</h1>
      </header>
      <div class="post-content">
        {{← param "content"}}
      </div>
    </article>
  }}

private def post : Template := do
  let catAddr ← do
    if let some p := (← param? (α := String) "path") then
      pure fun slug => p ++ "/" ++ slug
    else
      pure fun slug => slug
  let metadataHtml :=
    match (← param? (α := Post.PartMetadata) "metadata") with
    | none => Html.empty
    | some md => renderMetadataFooter catAddr md.date md.categories
  pure {{
    <article>
      <header class="post-header">
        <h1 class="post-title">{{← param "title"}}</h1>
        {{metadataHtml}}
        <div class="share-section">
          <div id="share-buttons" class="share-buttons"></div>
        </div>
      </header>
      <div class="post-content">
        {{← param "content"}}
      </div>
      <script>{{shareScript}}</script>
    </article>
  }}

private def category : Template := do
  let category : Post.Category ← param "category"
  pure {{
    <div class="tags-page">
      <h1>{{category.name}}</h1>
    </div>
  }}

private def archiveEntry : Template := do
  let post : BlogPost ← param "post"
  let summary ← param "summary"
  let target ←
    if let some p := (← param? (α := String) "path") then
      pure <| p ++ "/" ++ (← post.postName')
    else
      post.postName'
  let catAddr ←
    if let some p := (← param? (α := String) "path") then
      pure fun slug => p ++ "/" ++ slug
    else
      pure fun slug => slug
  let metadataHtml :=
    match post.contents.metadata with
    | none => Html.empty
    | some md => renderMetadataFooter catAddr md.date md.categories
  pure #[{{
    <div class="post-entry">
      <header class="entry-header">
        <h2><a href={{target}}>{{post.contents.titleString}}</a></h2>
      </header>
      {{metadataHtml}}
      <div class="entry-content">
        {{summary}}
      </div>
      <a class="entry-link" href={{target}} aria-label={{post.contents.titleString}}></a>
    </div>
  }}]

/-- PaperMod-inspired theme. -/
def chalkTheme : Theme :=
  { Theme.default with
    primaryTemplate := primary
    pageTemplate := page
    postTemplate := post
    categoryTemplate := category
    archiveEntryTemplate := archiveEntry }

end Site
