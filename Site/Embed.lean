import VersoBlog

open Verso Genre Blog
open Verso Output Html

block_component +directive iframe (src : String) where
  toHtml _id _json _goI _goB _contents := do
    pure {{
      <iframe src={{src}}
        style="width: 100%; height: 620px; border: 1px solid #e0e0e0; border-radius: 6px;"
        loading="lazy"
        allowfullscreen="true">
      </iframe>
    }}

/-- An iframe that grows to whatever height its page reports.

    The embedded page posts `{figHeight}` to its parent on load and on resize;
    the listener below resizes the matching frame. `height` is the fallback
    used until the first message arrives, and if the page never posts one. -/
block_component +directive figframe (src : String) (height : String) where
  toHtml _id _json _goI _goB _contents := do
    pure {{
      <div class="figframe">
        <iframe src={{src}} style={{s!"width:100%;height:{height}px;border:1px solid #e0e0e0;border-radius:6px;display:block"}}
          loading="lazy" scrolling="no">
        </iframe>
        <script>{{.text false "
          if (!window.__figFrameWired) {
            window.__figFrameWired = true;
            window.addEventListener('message', function (event) {
              var height = event.data && event.data.figHeight;
              if (!height) return;
              document.querySelectorAll('.figframe iframe').forEach(function (frame) {
                if (frame.contentWindow === event.source) frame.style.height = height + 'px';
              });
            });
          }
        "}}</script>
      </div>
    }}

block_component +directive hero (alt : String) (src : String) where
  toHtml _id _json _goI _goB _contents := do
    pure {{
      <div class="hero-image">
        <img src={{src}} alt={{alt}} />
      </div>
    }}

/-- Replace backtick-delimited spans with `<code>` tags. -/
private def renderInlineCode (s : String) : String :=
  let parts := s.splitOn "`"
  let (result, _) := parts.foldl (fun (acc, inCode) part =>
    if inCode then (acc ++ s!"<code>{part}</code>", false)
    else (acc ++ part, true)
  ) ("", false)
  result

/-- Render a pipe-delimited table from a raw string.
    First line is the header row, remaining lines are body rows.
    Columns are separated by `|`. Leading/trailing `|` are stripped.
    Backtick-delimited spans within cells are rendered as `<code>`. -/
private def parsePipeTable (src : String) : Html :=
  let lines := src.splitOn "\n" |>.map (·.trimAscii.toString) |>.filter (· != "")
  let stripEdge (line : String) : String :=
    let s := if line.startsWith "|" then (line.toSlice.drop 1).toString else line
    if s.endsWith "|" then (s.toSlice.dropEnd 1).toString else s
  let parseRow (line : String) : List String :=
    (stripEdge line).splitOn "|" |>.map (·.trimAscii.toString)
  let isSep (cells : List String) : Bool :=
    cells.all fun c => c.all fun ch => ch == '-' || ch == ':' || ch == ' '
  let rows := lines.map parseRow |>.filter (! isSep ·)
  match rows with
  | [] => .empty
  | hdr :: body =>
    let th := String.join (hdr.map fun c => s!"<th>{renderInlineCode c}</th>")
    let trs := body.map fun row =>
      let tds := String.join (row.map fun c => s!"<td>{renderInlineCode c}</td>")
      s!"<tr>{tds}</tr>"
    let html := s!"<table><thead><tr>{th}</tr></thead><tbody>{String.join trs}</tbody></table>"
    .text false html

/-- A pipe-delimited table. Pass the full table (header + separator + rows) as a string argument.
    Example: `:::pipeTable "Name | Value\n---|---\nfoo | 42"` -/
block_component +directive pipeTable (src : String) where
  toHtml _id _json _goI _goB _contents := do
    pure (parsePipeTable src)
