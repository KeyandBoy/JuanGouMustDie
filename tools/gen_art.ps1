# ============================================================
# AI image generation pipeline (reusable)
# ------------------------------------------------------------
# Primary : imagefree.net   POST /api/generate -> GET /api/generate/status?taskId=
# Fallback: pollinations.ai GET  /prompt/<urlencoded>
# Post    : tools/post_art.gd (magenta keying / trim / resize / save)
#
# NOTE: this file must stay pure ASCII. PowerShell 5.1 decodes
#       BOM-less UTF-8 scripts as ANSI/GBK, and CJK comments can
#       corrupt parsing. Chinese docs live in tools/ART_PIPELINE.md.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools\gen_art.ps1
#   powershell -ExecutionPolicy Bypass -File tools\gen_art.ps1 -Only tyrant_front
#   powershell -ExecutionPolicy Bypass -File tools\gen_art.ps1 -Manifest my.json -Post
#   powershell -ExecutionPolicy Bypass -File tools\gen_art.ps1 -Force
#
# Manifest (JSON array; only name/prompt required):
#   [{
#     "name":     "tyrant_front",          # output tools/_gen/<name>.png
#     "prompt":   ".....",
#     "ratio":    "3:4",                   # 16:9 | 4:3 | 3:4 | 1:1 (default 1:1)
#     "out":      "res://art/x/y.png",     # post-process destination
#     "key":      true,                    # magenta chroma key
#     "resize_h": 192                      # target height when key=true
#   }]
#
# Notes:
#   - imagefree rate-limits per IP (FREE_TASK_IP_ACTIVE): generate serially.
#   - The website sends turnstile_token; omitting it currently still works.
#   - Existing tools/_gen/<name>.png is skipped unless -Force.
# ============================================================
param(
  [string]$Only = "",
  [string]$Manifest = "",
  [switch]$Force,
  [switch]$Post,
  [string]$Godot = "E:\computerProgram2\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$raw = Join-Path $root "tools\_gen"
New-Item -ItemType Directory -Force -Path $raw | Out-Null
$manifestPath = Join-Path $raw "_manifest.json"

# ---------------- default manifest (this project) ----------------
$defaults = @(
  [pscustomobject]@{ name = "tyrant_front"; ratio = "3:4"; key = $true; resize_h = 192
    out = "res://art/sprites/tyrant/tyrant_front.png"
    prompt = "Full body game sprite of a huge muscular humanoid monster inspired by classic survival-horror tyrant villains: bald scarred head, pale grey necrotic skin, one enormous mutated arm, tattered dark suit shreds, wrapped in swirling black smoke, standing upright facing the viewer, dark moody rim light, high contrast, isolated on a solid flat magenta background, no ground shadow, no text" },
  [pscustomobject]@{ name = "tyrant_chase"; ratio = "3:4"; key = $true; resize_h = 192
    out = "res://art/sprites/tyrant/tyrant_chase.png"
    prompt = "Full body game sprite of the same huge muscular humanoid tyrant monster running forward with one giant mutated arm reaching out, swirling black smoke trailing behind, dark tattered clothes, pale grey skin, menacing, isolated on a solid flat magenta background, no ground shadow, no text" },
  [pscustomobject]@{ name = "intro_classroom"; ratio = "16:9"; key = $false
    out = "res://art/cutscene/intro_classroom.png"
    prompt = "First person view waking up on the floor of an old Chinese school classroom, rows of wooden desks, dusty chalkboard, harsh overhead fluorescent light, desaturated sickly colours, slight vignette, unsettling silent-hill style atmosphere, cinematic, no people, no text" },
  [pscustomobject]@{ name = "intro_board"; ratio = "16:9"; key = $false
    out = "res://art/cutscene/intro_board.png"
    prompt = "Close up of a dark green chalkboard in an empty classroom, wet chalk dust smeared across the surface, single hard light beam from the side, deep shadows, ominous mood, no writing, no letters, no text, cinematic" },
  [pscustomobject]@{ name = "intro_hall"; ratio = "16:9"; key = $false
    out = "res://art/cutscene/intro_hall.png"
    prompt = "Long empty school corridor at dusk, rows of identical doors, flickering fluorescent lights, cold fog drifting along the floor, vanishing point in darkness, psychological horror atmosphere, desaturated palette, cinematic, no people, no text" },
  [pscustomobject]@{ name = "tyrant_p1"; ratio = "4:3"; key = $false
    out = "res://art/cutscene/tyrant_p1.png"
    prompt = "Black and white comic panel with red accents: a long school corridor, walls cracking, dust falling from the ceiling, sense of heavy footsteps approaching, high contrast ink style, no text" },
  [pscustomobject]@{ name = "tyrant_p2"; ratio = "4:3"; key = $false
    out = "res://art/cutscene/tyrant_p2.png"
    prompt = "Black and white comic panel with red accents: a concrete classroom wall bursting open from behind, debris flying toward the viewer, a huge dark silhouette stepping through the hole, high contrast ink style, no text" },
  [pscustomobject]@{ name = "tyrant_p3"; ratio = "4:3"; key = $false
    out = "res://art/cutscene/tyrant_p3.png"
    prompt = "Black and white comic panel with red accents: a massive muscular humanoid monster with pale skin and one giant arm looming over a small crouching student, extreme low angle, dramatic shadows, high contrast ink style, no text" },
  [pscustomobject]@{ name = "tyrant_p4"; ratio = "4:3"; key = $false
    out = "res://art/cutscene/tyrant_p4.png"
    prompt = "Black and white comic panel with red accents: a student sprinting out through a classroom door into a dark corridor, motion lines, panic, high contrast ink style, no text" },
  [pscustomobject]@{ name = "ending_placeholder"; ratio = "16:9"; key = $false
    out = "res://art/cutscene/ending_placeholder.png"
    prompt = "Empty school stairwell leading upward into warm dawn light, dust motes floating, calm and hopeful mood, soft glow, cinematic, no people, no text" }
)

# ---------------- load manifest ----------------
if ($Manifest -ne "") {
  $mp = $Manifest
  if (-not [IO.Path]::IsPathRooted($mp)) { $mp = Join-Path $root $mp }
  if (-not (Test-Path -LiteralPath $mp)) { Write-Output "manifest not found: $mp"; exit 1 }
  # PS5.1 quirk: ConvertFrom-Json emits a JSON array as ONE Object[] pipeline
  # item. Wrapping the pipeline with @( ) would nest it into a 1-element
  # array, so assign first (yields Object[] directly) and only wrap the
  # non-array single-object case.
  $parsed = Get-Content -LiteralPath $mp -Raw -Encoding UTF8 | ConvertFrom-Json
  $assets = @($parsed)
  Write-Output "[manifest] $mp ($($assets.Count) entries)"
} else {
  $assets = $defaults
}

if ($Only -ne "") {
  $assets = @($assets | Where-Object { $_.name -eq $Only })
  if ($assets.Count -eq 0) { Write-Output "no such asset: $Only"; exit 1 }
}

# normalize optional fields
foreach ($a in $assets) {
  if (-not $a.PSObject.Properties["ratio"])    { $a | Add-Member -NotePropertyName ratio    -NotePropertyValue "1:1" }
  if (-not $a.PSObject.Properties["key"])      { $a | Add-Member -NotePropertyName key      -NotePropertyValue $false }
  if (-not $a.PSObject.Properties["resize_h"]) { $a | Add-Member -NotePropertyName resize_h -NotePropertyValue 192 }
}

# persist manifest for post_art.gd (skip when -Only, to avoid shrinking it)
if ($Only -eq "") {
  # $assets is already Object[]. Pass the variable directly (NOT @($assets),
  # which re-enumerates into the param list and collapses the array into a
  # single object). -NoEnumerate keeps ConvertTo-Json emitting a real array.
  $json = ConvertTo-Json -InputObject $assets -Depth 6 -Compress:$false
  [IO.File]::WriteAllText($manifestPath, $json, (New-Object Text.UTF8Encoding($false)))
  Write-Output "[manifest] wrote $manifestPath"
}

# ---------------- generation ----------------
function Get-ImageFree($prompt, $ratio) {
  $body = @{ prompt = $prompt; aspect_ratio = $ratio } | ConvertTo-Json -Compress
  $r = Invoke-WebRequest -Uri 'https://imagefree.net/api/generate' -Method Post -Body ([Text.Encoding]::UTF8.GetBytes($body)) -ContentType 'application/json' -UseBasicParsing -TimeoutSec 60
  $j = $r.Content | ConvertFrom-Json
  if (-not $j.taskId) { throw "no taskId: $($r.Content)" }
  $taskId = $j.taskId
  foreach ($i in 1..40) {
    Start-Sleep -Seconds 3
    $s = Invoke-WebRequest -Uri ("https://imagefree.net/api/generate/status?taskId=" + $taskId) -UseBasicParsing -TimeoutSec 45
    $sj = $s.Content | ConvertFrom-Json
    if ($sj.status -eq "completed" -and $sj.image) { return $sj.image }
    if ($sj.status -eq "failed") { throw "task failed" }
  }
  throw "timeout polling task"
}

function Get-Pollinations($prompt, $ratio) {
  $w = 1024; $h = 1024
  switch ($ratio) {
    "16:9" { $w = 1024; $h = 576 }
    "4:3"  { $w = 1024; $h = 768 }
    "3:4"  { $w = 768;  $h = 1024 }
    "1:1"  { $w = 1024; $h = 1024 }
  }
  $enc = [Uri]::EscapeDataString($prompt)
  return "https://image.pollinations.ai/prompt/$enc" + "?width=$w&height=$h&nologo=true&model=flux"
}

$okCount = 0
$failCount = 0
foreach ($a in $assets) {
  $name = [string]$a.name
  $ratio = [string]$a.ratio
  $prompt = [string]$a.prompt
  $dest = Join-Path $raw ($name + ".png")
  if ((Test-Path $dest) -and (-not $Force)) {
    Write-Output "[skip] $name (already generated, use -Force to redo)"
    $okCount++
    continue
  }
  $url = $null
  try {
    $url = Get-ImageFree $prompt $ratio
    Write-Output "[imagefree] $name -> $url"
  } catch {
    Write-Output "[imagefree FAILED] $name : $($_.Exception.Message)"
    try {
      $url = Get-Pollinations $prompt $ratio
      Write-Output "[pollinations] $name -> $url"
    } catch {
      Write-Output "[pollinations FAILED] $name : $($_.Exception.Message)"
      $failCount++
      continue
    }
  }
  try {
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 120
    Write-Output "  saved $dest ($((Get-Item $dest).Length) bytes)"
    $okCount++
  } catch {
    Write-Output "  download FAILED : $($_.Exception.Message)"
    $failCount++
  }
  Start-Sleep -Seconds 1
}

Write-Output "GEN done ok=$okCount fail=$failCount"

# ---------------- optional post-process ----------------
if ($Post) {
  if (-not (Test-Path -LiteralPath $Godot)) {
    Write-Output "[post] godot not found: $Godot"
  } else {
    Write-Output "[post] running post_art.gd"
    & $Godot --headless --path $root --script res://tools/post_art.gd
  }
}
