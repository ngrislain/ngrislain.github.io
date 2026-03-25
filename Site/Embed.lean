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

block_component +directive hero (alt : String) (src : String) where
  toHtml _id _json _goI _goB _contents := do
    pure {{
      <div class="hero-image">
        <img src={{src}} alt={{alt}} />
      </div>
    }}

/-- Render a pipe-delimited table from a raw string.
    First line is the header row, remaining lines are body rows.
    Columns are separated by `|`. Leading/trailing `|` are stripped. -/
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
    let th := String.join (hdr.map fun c => s!"<th>{c}</th>")
    let trs := body.map fun row =>
      let tds := String.join (row.map fun c => s!"<td>{c}</td>")
      s!"<tr>{tds}</tr>"
    let html := s!"<table><thead><tr>{th}</tr></thead><tbody>{String.join trs}</tbody></table>"
    .text false html

/-- A pipe-delimited table. Pass the full table (header + separator + rows) as a string argument.
    Example: `:::pipeTable "Name | Value\n---|---\nfoo | 42"` -/
block_component +directive pipeTable (src : String) where
  toHtml _id _json _goI _goB _contents := do
    pure (parsePipeTable src)
