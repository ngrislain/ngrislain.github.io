import VersoBlog
import Site.Front
import Site.About
import Site.Theme
import Site.Feed
import Site.Projects
import Site.Projects.Adventure
import Site.Projects.AIEconomics
import Site.Projects.TypeDrivenDev
import Site.Blog
import Site.Embed
import Site.Blog.PrefixScan

open Verso Genre Blog Site Syntax

def personalSite : Site :=
  site Site.Front /
    static "static" ← "static"
    "about" Site.About
    "blog" Site.Blog with
      Site.Blog.PrefixScan
    "projects" Site.Projects with
      Site.Projects.TypeDrivenDev
      Site.Projects.AIEconomics
      Site.Projects.Adventure

def main (args : List String) : IO UInt32 := do
  let rc ← blogMain Site.chalkTheme personalSite (options := args)
  Site.Feed.generate "build"
  return rc
