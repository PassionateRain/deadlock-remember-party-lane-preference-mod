# Copies the working files into repo\ (the git checkout) so they can be committed.
# Working copy (edit these): src\mod, tools\*.ps1, docs\index.html, NOTES.md
# Repo-only files (edit in repo\ directly): README.md, MAINTENANCE.md, LICENSE, .gitignore
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$repo = Join-Path $root 'repo'

Remove-Item -Recurse -Force (Join-Path $repo 'src\mod') -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force (Join-Path $repo 'src'), (Join-Path $repo 'tools'), (Join-Path $repo 'docs') | Out-Null
Copy-Item -Recurse (Join-Path $root 'src\mod') (Join-Path $repo 'src\mod')
Copy-Item (Join-Path $root 'tools\*.ps1') (Join-Path $repo 'tools')
Copy-Item (Join-Path $root 'docs\index.html') (Join-Path $repo 'docs\index.html')
Copy-Item (Join-Path $root 'NOTES.md') (Join-Path $repo 'NOTES.md')

Push-Location $repo
try { git status --short } finally { Pop-Location }
