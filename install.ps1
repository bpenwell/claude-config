<#
.SYNOPSIS
  Install this Claude Code configuration into $HOME\.claude on Windows.

.DESCRIPTION
  Copies hooks and skills into ~/.claude, renders settings.json with this
  machine's absolute hooks path, and merges MCP servers into ~/.claude.json
  using credentials from an env file kept outside the repo.

  Anything already at a target path is moved to
  ~/.claude/backups/install-<timestamp>\ before being replaced. Nothing is
  deleted, and re-running is safe.

.PARAMETER Link
  Use symbolic links instead of copies, so 'git pull' updates the live config.
  Requires Windows Developer Mode or an elevated shell; falls back to copying
  per item if a link cannot be created.

.PARAMETER DryRun
  Print every action without changing anything.

.EXAMPLE
  .\install.ps1
.EXAMPLE
  .\install.ps1 -Link -DryRun
#>
[CmdletBinding()]
param(
  [switch]$Link,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$Repo = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($env:CLAUDE_CONFIG_DIR) { $ClaudeDir = $env:CLAUDE_CONFIG_DIR } else { $ClaudeDir = Join-Path $HOME '.claude' }
if ($env:CLAUDE_CONFIG_ENV) { $EnvFile = $env:CLAUDE_CONFIG_ENV } else { $EnvFile = Join-Path $HOME '.claude-config.env' }
$BackupDir = Join-Path $ClaudeDir ("backups\install-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Write-Error 'node is required but was not found on PATH.'
  exit 1
}

# Probe symlink support once rather than failing per item: without Developer Mode
# or elevation, Windows refuses to create symbolic links.
if ($Link) {
  $probeTarget = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
  $probeLink = "$probeTarget.link"
  try {
    New-Item -ItemType Directory -Force -Path $probeTarget | Out-Null
    New-Item -ItemType SymbolicLink -Path $probeLink -Target $probeTarget -ErrorAction Stop | Out-Null
  } catch {
    Write-Host 'Symlinks unavailable (needs Windows Developer Mode or an elevated shell); installing as copies.'
    $Link = $false
  } finally {
    Remove-Item -LiteralPath $probeLink -Force -Recurse -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $probeTarget -Force -Recurse -ErrorAction SilentlyContinue
  }
}

function Invoke-Step {
  param([string]$Description, [scriptblock]$Action)
  if ($DryRun) { Write-Host "  [dry-run] $Description" }
  else { & $Action }
}

function Backup-Existing {
  param([string]$Target, [string]$Source)
  $item = Get-Item -LiteralPath $Target -Force -ErrorAction SilentlyContinue
  if (-not $item) { return $true }

  # A link already pointing at this source needs no backup and no redo.
  if ($item.LinkType -and $item.Target) {
    $current = @($item.Target)[0]
    if ($Source -and ($current.TrimEnd('\','/') -eq $Source.TrimEnd('\','/'))) { return $false }
  }

  # Copy mode: identical contents means there is nothing to back up or redo.
  if ($Source -and -not $Link) {
    & node (Join-Path $Repo 'scripts\same-tree.mjs') $Source $Target 2>$null
    if ($LASTEXITCODE -eq 0) { return $false }
  }

  Invoke-Step "move $Target -> $BackupDir\" {
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    Move-Item -LiteralPath $Target -Destination (Join-Path $BackupDir (Split-Path $Target -Leaf)) -Force
  }
  Write-Host "  backed up existing $(Split-Path $Target -Leaf) -> $BackupDir\"
  return $true
}

function Install-Item {
  param([string]$Source, [string]$Target)
  $name = Split-Path $Target -Leaf
  if (-not (Backup-Existing -Target $Target -Source $Source)) {
    Write-Host "  $name already up to date"
    return
  }

  if ($Link) {
    if ($DryRun) { Write-Host "  [dry-run] link $Target -> $Source"; return }
    New-Item -ItemType SymbolicLink -Path $Target -Target $Source -Force | Out-Null
    Write-Host "  linked $name"
    return
  }

  Invoke-Step "copy $Source -> $Target" {
    Copy-Item -LiteralPath $Source -Destination $Target -Recurse -Force
  }
  Write-Host "  copied $name"
}

Write-Host "Installing Claude config from $Repo into $ClaudeDir (mode: $(if ($Link) {'symlink'} else {'copy'}))"
Invoke-Step "create $ClaudeDir" { New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null }

Write-Host 'hooks:'
Install-Item -Source (Join-Path $Repo 'hooks') -Target (Join-Path $ClaudeDir 'hooks')

Write-Host 'settings:'
# settings.json is rendered, not linked: hook commands need an absolute path to
# the hooks directory, which differs per machine. Use this to pull in-app
# preference changes back into the template: node scripts\sync-settings.mjs
$settingsTarget = Join-Path $ClaudeDir 'settings.json'
$renderArgs = @(
  (Join-Path $Repo 'scripts\render-settings.mjs'),
  '--template', (Join-Path $Repo 'settings\settings.template.json'),
  '--hooks-dir', (Join-Path $ClaudeDir 'hooks'),
  '--out', $settingsTarget,
  '--backup-dir', $BackupDir
)
if ($DryRun) { $renderArgs += '--dry-run' }
& node $renderArgs
if ($LASTEXITCODE -ne 0) { throw "render-settings failed with exit code $LASTEXITCODE" }

Write-Host 'skills:'
# Merged per-directory so skills that exist only on this machine survive.
$skillsDir = Join-Path $ClaudeDir 'skills'
Invoke-Step "create $skillsDir" { New-Item -ItemType Directory -Force -Path $skillsDir | Out-Null }
Get-ChildItem -Directory (Join-Path $Repo 'skills') | ForEach-Object {
  Install-Item -Source $_.FullName -Target (Join-Path $skillsDir $_.Name)
}

Write-Host 'mcp servers:'
if (Test-Path -LiteralPath $EnvFile) {
  $mcpArgs = @((Join-Path $Repo 'mcp\merge-mcp.mjs'), '--env-file', $EnvFile)
  if ($DryRun) { $mcpArgs += '--dry-run' }
  & node $mcpArgs
  if ($LASTEXITCODE -ne 0) { throw "merge-mcp failed with exit code $LASTEXITCODE" }
} else {
  Write-Host "  skipped: no $EnvFile"
  Write-Host "  copy $Repo\mcp\env.example $EnvFile, fill it in, then re-run .\install.ps1"
}

Write-Host ''
Write-Host 'Done. Remaining manual steps:'
Write-Host '  1. Plugins install on first launch from settings.json (enabledPlugins). If the'
Write-Host '     official marketplace is missing, run: claude  ->  /plugin marketplace add anthropics/claude-code'
Write-Host '  2. Restart Claude Code so hooks and MCP servers are picked up.'
