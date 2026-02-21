import VersoBlog
import Site.Front
import Site.About
import Site.Theme
import Site.Projects
import Site.Projects.Adventure
import Site.Projects.AIEconomics

open Verso Genre Blog Site Syntax

def personalSite : Site :=
  site Site.Front /
    static "static" ← "static"
    "about" Site.About
    "projects" Site.Projects with
      Site.Projects.AIEconomics
      Site.Projects.Adventure

def main :=
  blogMain Site.chalkTheme personalSite
