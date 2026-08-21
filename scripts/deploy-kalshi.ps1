<#
.SYNOPSIS
  Ship kalshi-flipper from this Windows box to the home server and (re)start it.

.DESCRIPTION
  Uses the tar.exe and ssh.exe that ship with Windows 10/11 — nothing to install.
  Secrets (keys/, deploy/*.env) are git-ignored but ARE included here, because the
  server needs them and they never touch a remote git host.

  Excluded: .git, node_modules, build output, the Windows .exe binaries, and data/
  (the server has its own SQLite — shipping yours would clobber live trade history).

.EXAMPLE
  .\deploy-kalshi.ps1
  .\deploy-kalshi.ps1 -ServerHost 192.168.1.50 -User hash -Logs
#>
[CmdletBinding()]
param(
  [string]$ServerHost = '192.168.1.50',
  [string]$User       = 'hash',
  [string]$RepoPath   = 'D:\AI\kalshi-flipper',
  [string]$RemoteDir  = '/srv/apps/kalshi/kalshi-flipper',
  [switch]$Logs
)

$ErrorActionPreference = 'Stop'
$target = "$User@$ServerHost"

if (-not (Test-Path $RepoPath)) { throw "repo not found: $RepoPath" }

# --- preflight: the server needs these three, and they are not in git -----------
foreach ($f in @('keys\.env', 'deploy\live.env', 'deploy\paper.env', 'deploy\proxy.env')) {
  if (-not (Test-Path (Join-Path $RepoPath $f))) {
    throw "missing $f — copy it from the matching .example and fill it in first"
  }
}
$proxy = Get-Content (Join-Path $RepoPath 'deploy\proxy.env') -Raw
if ($proxy -match 'REPLACE_WITH_BCRYPT_HASH') {
  throw 'deploy\proxy.env still has the placeholder BASIC_AUTH_HASH'
}

Write-Host "==> $target : preparing $RemoteDir"
ssh $target "mkdir -p $RemoteDir"

$excludes = @(
  '--exclude=.git', '--exclude=node_modules', '--exclude=web/node_modules',
  '--exclude=web/dist', '--exclude=data', '--exclude=*.exe', '--exclude=*.exe~',
  '--exclude=.venv', '--exclude=__pycache__', '--exclude=ml/data'
)

Write-Host '==> streaming source over ssh'
Push-Location $RepoPath
try {
  # tar to stdout | ssh | tar from stdin. No temp file, no rsync needed.
  & tar -czf - @excludes . | & ssh $target "tar -xzf - -C $RemoteDir"
  if ($LASTEXITCODE -ne 0) { throw "transfer failed (exit $LASTEXITCODE)" }
} finally { Pop-Location }

Write-Host '==> build + restart on the server'
ssh $target "chmod +x /srv/homeserver/scripts/kalshi.sh && /srv/homeserver/scripts/kalshi.sh up"

Write-Host ''
Write-Host "==> dashboard: https://kalshi.<your-domain>   (over WireGuard or on the LAN)"
Write-Host "    logs:      ssh $target '/srv/homeserver/scripts/kalshi.sh logs'"

if ($Logs) { ssh -t $target "/srv/homeserver/scripts/kalshi.sh logs" }
