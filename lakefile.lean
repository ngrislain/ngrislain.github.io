import Lake
open Lake DSL

package «ngrislain-github-io» where
  moreLeanArgs := #["-DwarningAsError=true"]

require «verso» from git
  "https://github.com/leanprover/verso.git" @ "main"

lean_lib «Ngrislain.Github.Io» where
  roots := #[`Site]

lean_exe «ngrislain-github-io» where
  root := `Site.Main
