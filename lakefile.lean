import Lake
open Lake DSL

package «ngrislain-github-io» where
  moreLeanArgs := #["-DwarningAsError=true"]

require «verso» from git
  "https://github.com/leanprover/verso.git" @ "v4.36.0"

lean_lib «Ngrislain.Github.Io» where
  roots := #[`Site]

@[default_target]
lean_exe «ngrislain-github-io» where
  root := `Site.Main
