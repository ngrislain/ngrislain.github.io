/-
  RSS feed generation.
  Scans the build output for dated post directories and produces feed.xml.
-/

namespace Site.Feed

def siteUrl : String := "https://ngrislain.github.io"
def siteTitle : String := "NGrislain"
def siteDesc : String := "Personal site of Nicolas Grislain"

private def escapeXml (s : String) : String :=
  s.replace "&" "&amp;" |>.replace "<" "&lt;" |>.replace ">" "&gt;" |>.replace "\"" "&quot;"

private def findSubstr (s : String) (sub : String) : Option Nat :=
  let sLen := s.length
  let subLen := sub.length
  if subLen > sLen then none
  else Id.run do
    for i in [:sLen - subLen + 1] do
      if ((s.drop i).take subLen).toString == sub then return some i
    return none

/-- Extract the text content of the first <h1 class="post-title"> from HTML. -/
private def extractTitle (html : String) : Option String := do
  let marker := "<h1 class=\"post-title\">"
  let start ← findSubstr html marker
  let rest := (html.drop (start + marker.length)).toString
  let stop ← findSubstr rest "</h1>"
  some ((rest.take stop).toString.trimAscii.toString)

/-- Extract first <p>...</p> text content from post-content div. -/
private def extractDesc (html : String) : String :=
  let marker := "<p>"
  match findSubstr html marker with
  | none => ""
  | some start =>
    let rest := (html.drop (start + marker.length)).toString
    match findSubstr rest "</p>" with
    | none => ""
    | some stop => (rest.take stop).toString.trimAscii.toString

/-- Parse date components from a directory name like "2026-3-13-some-title". -/
private def parseDate (dirName : String) : Option (Nat × Nat × Nat) := do
  let parts := dirName.splitOn "-"
  guard (parts.length ≥ 3)
  let year ← parts[0]!.toNat?
  let month ← parts[1]!.toNat?
  let day ← parts[2]!.toNat?
  some (year, month, day)

private def monthAbbrev : Nat → String
  | 1 => "Jan" | 2 => "Feb" | 3 => "Mar" | 4 => "Apr"
  | 5 => "May" | 6 => "Jun" | 7 => "Jul" | 8 => "Aug"
  | 9 => "Sep" | 10 => "Oct" | 11 => "Nov" | 12 => "Dec"
  | _ => "Jan"

private def pad2 (n : Nat) : String :=
  if n < 10 then s!"0{n}" else toString n

private def formatRssDate (year month day : Nat) : String :=
  s!"{pad2 day} {monthAbbrev month} {year} 00:00:00 +0000"

structure FeedItem where
  title : String
  url : String
  date : String
  sortKey : Nat
  desc : String

/-- Collect feed items from a single section directory. -/
private def collectFromSection (buildDir : System.FilePath) (sect : String) : IO (Array FeedItem) := do
  let sectDir := buildDir / sect
  let dirExists ← sectDir.pathExists
  if !dirExists then return #[]
  let entries ← sectDir.readDir
  let mut items : Array FeedItem := #[]
  for entry in entries do
    let dirName := entry.fileName
    match parseDate dirName with
    | none => pure ()
    | some (year, month, day) =>
      let indexFile := entry.path / "index.html"
      let fileExists ← indexFile.pathExists
      if fileExists then
        let html ← IO.FS.readFile indexFile
        match extractTitle html with
        | none => pure ()
        | some title =>
          let url := s!"{siteUrl}/{sect}/{dirName}/"
          let date := formatRssDate year month day
          let sortKey := year * 10000 + month * 100 + day
          let desc := extractDesc html
          items := items.push { title, url, date, sortKey, desc }
  return items

/-- Collect feed items by scanning the build directory for dated post directories. -/
private def collectFeedItems (buildDir : System.FilePath) : IO (Array FeedItem) := do
  let mut items : Array FeedItem := #[]
  for sect in #["blog", "projects"] do
    let sectItems ← collectFromSection buildDir sect
    items := items ++ sectItems
  return items.qsort (·.sortKey > ·.sortKey)

/-- Generate RSS feed XML from the build output directory. -/
def generate (buildDir : System.FilePath) : IO Unit := do
  let items ← collectFeedItems buildDir
  let mut xml := "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
  xml := xml ++ "<rss version=\"2.0\" xmlns:atom=\"http://www.w3.org/2005/Atom\">\n<channel>\n"
  xml := xml ++ s!"<title>{escapeXml siteTitle}</title>\n"
  xml := xml ++ s!"<link>{siteUrl}</link>\n"
  xml := xml ++ s!"<description>{escapeXml siteDesc}</description>\n"
  xml := xml ++ s!"<atom:link href=\"{siteUrl}/feed.xml\" rel=\"self\" type=\"application/rss+xml\"/>\n"
  xml := xml ++ "<language>en</language>\n"
  for item in items do
    xml := xml ++ "<item>\n"
    xml := xml ++ s!"<title>{escapeXml item.title}</title>\n"
    xml := xml ++ s!"<link>{item.url}</link>\n"
    xml := xml ++ s!"<guid>{item.url}</guid>\n"
    xml := xml ++ s!"<pubDate>{item.date}</pubDate>\n"
    xml := xml ++ s!"<description>{escapeXml item.desc}</description>\n"
    xml := xml ++ "</item>\n"
  xml := xml ++ "</channel>\n</rss>\n"
  IO.FS.writeFile (buildDir / "feed.xml") xml
  IO.println s!"Generated {buildDir / "feed.xml"} with {items.size} items"

end Site.Feed
