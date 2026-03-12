import VersoBlog
import Site.Front
import Site.About
import Site.Theme
import Site.Projects
import Site.Projects.Adventure
import Site.Projects.AIEconomics
import Site.Projects.TypeDrivenDev

open Verso Genre Blog Site Syntax

def personalSite : Site :=
  site Site.Front /
    static "static" ← "static"
    "about" Site.About
    "projects" Site.Projects with
      Site.Projects.TypeDrivenDev
      Site.Projects.AIEconomics
      Site.Projects.Adventure

def main :=
  blogMain Site.chalkTheme personalSite
