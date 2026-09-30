/-
  Cloudflare Web Analytics injection.
  Post-processes standalone static HTML files (interactive demos, figures)
  that are served directly and don't go through Site.Theme's page template.
-/

namespace Site.Analytics

private def snippet : String :=
  "<!-- Cloudflare Web Analytics -->" ++
  "<script type=\"module\" src=\"https://static.cloudflareinsights.com/beacon.min.js\" " ++
  "data-cf-beacon='{\"token\": \"2a206424538c4f8da18ef6ec2879e136\"}'></script>" ++
  "<!-- End Cloudflare Web Analytics -->"

/-- Character index of the first occurrence of `sub` in `s`. Linear time
    (a naive `drop i` loop is quadratic and hangs on multi-MB files). -/
private def findSubstr (s : String) (sub : String) : Option Nat :=
  match s.splitOn sub with
  | first :: _ :: _ => some first.length
  | _ => none

/-- Insert the snippet before the last `</body>`, or append it if the file has none. -/
private def processFile (filePath : System.FilePath) : IO Unit := do
  let html ← IO.FS.readFile filePath
  if (findSubstr html "cloudflareinsights.com").isSome then return
  match findSubstr html "</body>" with
  | some bodyEnd =>
    let before := (html.take bodyEnd).toString
    let after := (html.drop bodyEnd).toString
    IO.FS.writeFile filePath (before ++ snippet ++ after)
  | none =>
    IO.FS.writeFile filePath (html ++ snippet)

private partial def walk (dir : System.FilePath) : IO Unit := do
  let entries ← dir.readDir
  for entry in entries do
    if ← entry.path.isDir then
      walk entry.path
    else if entry.fileName.endsWith ".html" then
      processFile entry.path

/-- Inject the Cloudflare Web Analytics snippet into every HTML file under `buildDir/static`. -/
def inject (buildDir : System.FilePath) : IO Unit := do
  let staticDir := buildDir / "static"
  if ← staticDir.pathExists then
    walk staticDir
    IO.println s!"Injected Cloudflare Analytics into static HTML pages"

end Site.Analytics
