param(
  [switch]$Clipboard,
  [string]$Start = "",
  [switch]$End,
  [string]$Intent = "",
  [switch]$Force
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$lockPath = Join-Path $root "SESSION.lock"

function Read-Lock {
  if (-not (Test-Path -LiteralPath $lockPath)) { return $null }
  try { return (Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

if ($Start.Length -gt 0) {
  $existing = Read-Lock
  if ($existing -ne $null -and -not $Force) {
    Write-Host ("LOCK BUSY: tool={0} started={1} intent={2}" -f $existing.tool, $existing.started_at, $existing.intent)
    Write-Host "Use -Force to override, or -End to clear the stale lock."
    exit 2
  }
  $obj = [ordered]@{
    tool = $Start
    started_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    intent = $Intent
    branch = (git branch --show-current 2>$null)
    host = $env:COMPUTERNAME
  }
  $json = $obj | ConvertTo-Json
  [IO.File]::WriteAllText($lockPath, $json, (New-Object Text.UTF8Encoding($false)))
  Write-Host ("LOCKED by {0}" -f $Start)
  if (-not $Clipboard) { exit 0 }
}

if ($End) {
  if (Test-Path -LiteralPath $lockPath) {
    Remove-Item -LiteralPath $lockPath -Force
    Write-Host "UNLOCKED"
  } else {
    Write-Host "No lock present."
  }
  exit 0
}

$branch = (git branch --show-current 2>$null)
$head = (git rev-parse --short HEAD 2>$null)
$status = @(git status --porcelain 2>$null)
$modified = @($status | Where-Object { $_ -match '^ M' }).Count
$untracked = @($status | Where-Object { $_ -match '^\?\?' }).Count
$keyFiles = @($status | Where-Object { $_ -notmatch '\.import$' -and $_ -notmatch '^ M tests/shot_' } | Select-Object -First 20)
$lock = Read-Lock

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# Handoff Brief")
[void]$sb.AppendLine("")
[void]$sb.AppendLine(("- generated: " + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")))
[void]$sb.AppendLine(("- branch: {0}    HEAD: {1}" -f $branch, $head))
[void]$sb.AppendLine(("- worktree: modified={0} untracked={1}" -f $modified, $untracked))
if ($lock -ne $null) {
  [void]$sb.AppendLine(("- session lock: tool={0} started={1} intent={2}" -f $lock.tool, $lock.started_at, $lock.intent))
} else {
  [void]$sb.AppendLine("- session lock: none")
}
[void]$sb.AppendLine("")

if ($keyFiles.Count -gt 0) {
  [void]$sb.AppendLine("## Changed files (non-import)")
  foreach ($f in $keyFiles) { [void]$sb.AppendLine(("- " + $f.Trim())) }
  [void]$sb.AppendLine("")
}

$handoffPath = Join-Path $root "HANDOFF.md"
if (Test-Path -LiteralPath $handoffPath) {
  $lines = Get-Content -LiteralPath $handoffPath -Encoding UTF8
  $capture = $false
  $next = New-Object System.Collections.Generic.List[string]
  foreach ($line in $lines) {
    if ($line -match 'NEXT_STEPS_START') { $capture = $true; continue }
    if ($line -match 'NEXT_STEPS_END') { $capture = $false; continue }
    if ($capture) { $next.Add($line) }
  }
  if ($next.Count -gt 0) {
    [void]$sb.AppendLine("## Next steps (from HANDOFF.md)")
    foreach ($n in $next) { [void]$sb.AppendLine($n) }
    [void]$sb.AppendLine("")
  }
}

$devPath = Join-Path $root (([char]0x5F00) + [char]0x53D1 + [char]0x8BB0 + [char]0x5F55 + ".md")
if (Test-Path -LiteralPath $devPath) {
  $lines = Get-Content -LiteralPath $devPath -Encoding UTF8
  $inChangelog = $false
  $found = New-Object System.Collections.Generic.List[string]
  foreach ($line in $lines) {
    if ($line -match '^##\s*6\.') { $inChangelog = $true; continue }
    if ($inChangelog -and $line -match '^##\s') { break }
    if ($inChangelog -and $line -match '^### ') {
      $found.Add($line)
      if ($found.Count -ge 3) { break }
    }
  }
  if ($found.Count -gt 0) {
    [void]$sb.AppendLine("## Recent changelog")
    foreach ($h in $found) { [void]$sb.AppendLine($h) }
    [void]$sb.AppendLine("")
  }
}

[void]$sb.AppendLine("## Tests")
[void]$sb.AppendLine('$G = "E:\computerProgram2\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"')
[void]$sb.AppendLine('& $G --headless --path . --quit-after 20000 res://tests/tutorial_test.tscn')
[void]$sb.AppendLine('& $G --headless --path . --quit-after 8000 res://tests/flow_test.tscn')
[void]$sb.AppendLine('& $G --headless --path . --quit-after 8000 res://tests/_stalkerprobe.tscn')
[void]$sb.AppendLine('& $G --headless --path . --quit-after 8000 res://tests/student_test.tscn')
[void]$sb.AppendLine('& $G --path . res://tests/screenshot.tscn')

$text = $sb.ToString()
if ($Clipboard) {
  if ($Start.Length -gt 0) {
    $promptPath = Join-Path $root "tools\DSH_PROMPT.txt"
    if (Test-Path -LiteralPath $promptPath) {
      $prompt = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8
      $text = $prompt.TrimEnd() + "`r`n`r`n" + $text
    }
  }
  Set-Clipboard -Value $text
  Write-Host "Copied handoff brief to clipboard."
}
Write-Output $text
