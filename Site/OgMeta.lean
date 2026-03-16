/-
  Open Graph / Twitter Card meta tag injection.
  Post-processes generated HTML files to add og:image, og:description, og:url
  and their Twitter equivalents.
-/

namespace Site.OgMeta

private def siteUrl : String := "https://ngrislain.github.io"

private def findSubstr (s : String) (sub : String) : Option Nat :=
  let sLen := s.length
  let subLen := sub.length
  if subLen > sLen then none
  else Id.run do
    for i in [:sLen - subLen + 1] do
      if ((s.drop i).take subLen).toString == sub then return some i
    return none

/-- Extract the src of the first <img in post-content div. -/
private def extractImage (html : String) : Option String := do
  let contentMarker := "post-content"
  let contentStart ← findSubstr html contentMarker
  let rest := (html.drop contentStart).toString
  let imgMarker := "<img"
  let imgStart ← findSubstr rest imgMarker
  let afterImg := (rest.drop imgStart).toString
  let srcMarker := "src=\""
  let srcStart ← findSubstr afterImg srcMarker
  let afterSrc := (afterImg.drop (srcStart + srcMarker.length)).toString
  let quoteEnd ← findSubstr afterSrc "\""
  some (afterSrc.take quoteEnd).toString

/-- Extract first <p>...</p> text content, stripping HTML tags. -/
private def extractDesc (html : String) : String :=
  let marker := "<p>"
  match findSubstr html marker with
  | none => ""
  | some start =>
    let rest := (html.drop (start + marker.length)).toString
    match findSubstr rest "</p>" with
    | none => ""
    | some stop =>
      let raw := (rest.take stop).toString.trimAscii.toString
      -- Strip HTML tags for a clean description
      Id.run do
        let mut result := ""
        let mut inTag := false
        for c in raw.toList do
          if c == '<' then
            inTag := true
          else if c == '>' then
            inTag := false
          else if !inTag then
            result := result.push c
        return result

/-- Escape HTML attribute content. -/
private def escapeAttr (s : String) : String :=
  s.replace "&" "&amp;" |>.replace "\"" "&quot;" |>.replace "<" "&lt;" |>.replace ">" "&gt;"

/-- Build OG meta tags string for a given page URL, description, and optional image. -/
private def buildMetaTags (url : String) (desc : String) (image? : Option String) : String :=
  let descEsc := escapeAttr desc
  let base := s!"<meta property=\"og:url\" content=\"{url}\"/>\n" ++
    s!"<meta property=\"og:description\" content=\"{descEsc}\"/>\n" ++
    s!"<meta name=\"twitter:description\" content=\"{descEsc}\"/>\n"
  match image? with
  | some img =>
    let absImg := if img.startsWith "http" then img
                  else s!"{siteUrl}/{img.dropWhile (· == '/')}"
    base ++ s!"<meta property=\"og:image\" content=\"{absImg}\"/>\n" ++
      s!"<meta name=\"twitter:image\" content=\"{absImg}\"/>\n"
  | none => base

/-- Inject OG meta tags into a single HTML file. -/
private def processFile (filePath : System.FilePath) (pageUrl : String) : IO Unit := do
  let html ← IO.FS.readFile filePath
  -- Find </head> to inject before it
  match findSubstr html "</head>" with
  | none => pure ()
  | some headEnd =>
    let desc := extractDesc html
    let image? := extractImage html
    if desc.isEmpty && image?.isNone then return
    let tags := buildMetaTags pageUrl desc image?
    let before := (html.take headEnd).toString
    let after := (html.drop headEnd).toString
    IO.FS.writeFile filePath (before ++ tags ++ after)

/-- Inject OG meta tags into all post HTML files in blog/ and projects/. -/
def inject (buildDir : System.FilePath) : IO Unit := do
  let mut count := 0
  for sect in #["blog", "projects"] do
    let sectDir := buildDir / sect
    let dirExists ← sectDir.pathExists
    if !dirExists then continue
    let entries ← sectDir.readDir
    for entry in entries do
      let indexFile := entry.path / "index.html"
      let fileExists ← indexFile.pathExists
      if fileExists then
        let dirName := entry.fileName
        let pageUrl := s!"{siteUrl}/{sect}/{dirName}/"
        processFile indexFile pageUrl
        count := count + 1
  IO.println s!"Injected OG meta tags into {count} pages"

end Site.OgMeta
