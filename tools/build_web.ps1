$ErrorActionPreference = "Stop"

$Godot = $env:GODOT
if (-not $Godot) { $Godot = "godot" }

New-Item -ItemType Directory -Force -Path "export/web" | Out-Null
& $Godot --headless --path . --export-release "Web" "export/web/index.html"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Web export written to export/web"
