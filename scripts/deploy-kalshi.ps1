<#
.SYNOPSIS
  Ship kalshi-flipper from this Windows box to the home server and (re)start it.

.DESCRIPTION
  Two lessons are baked into how this works:

  1. It uses `git archive`, not `tar`, to collect the source. The working tree
     carries gigabytes of untracked Parquet tick archives -- even `du` on it times
     out, and a `tar --exclude` list is guesswork. `git archive HEAD` emits exactly
     the tracked files (~1 MB) by construction.

  2. It writes a temp file and `scp`s it, rather than piping tar through the
     pipeline. PowerShell re-encodes bytes as text between native commands, which
     silently corrupts a binary/gzip stream.

  The five secret files are git-ignored, so they are copied separately. They never
  touch a remote git host.

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

# --- preflight: the server needs these, and they are not in git -----------------
$secrets = @('keys\.env', 'deploy\live.env', 'deploy\paper.env', 'deploy\proxy.env')
foreach ($f in $secrets) {
  if (-not (Test-Path (Join-Path $RepoPath $f))) {
    throw "missing $f -- copy it from the matching .example and fill it in first"
  }
}

$proxy = Get-Content (Join-Path $RepoPath 'deploy\proxy.env') -Raw
if ($proxy -match 'REPLACE_WITH_BCRYPT_HASH') {
  throw 'deploy\proxy.env still has the placeholder BASIC_AUTH_HASH'
}
# Docker Compose v5 interpolates env_file values, so a raw bcrypt hash gets its
# $-segments eaten and Caddy 401s every login with "hashedSecret too short".
if ($proxy -match 'BASIC_AUTH_HASH=\$(?!\$)') {
  throw @'
deploy\proxy.env: BASIC_AUTH_HASH has single $ characters.

Docker Compose v5 interpolates env_file values, so $2a$14$Ryh... becomes $2a$14$
and every dashboard login fails with 401. Double every dollar sign:

    BASIC_AUTH_HASH=$$2a$$14$$Ryh...
'@
}

# --- the Kalshi private key referenced by keys/.env must exist ------------------
$keyLine = (Get-Content (Join-Path $RepoPath 'keys\.env') | Select-String '^KALSHI_API_KEY=').Line
if ($keyLine) {
  $keyRel = ($keyLine -split '=', 2)[1].Trim('"', "'", ' ')
  if ($keyRel -and -not (Test-Path (Join-Path $RepoPath $keyRel))) {
    throw "keys\.env points KALSHI_API_KEY at '$keyRel', which does not exist"
  }
}

Write-Host "==> $target : preparing $RemoteDir"
ssh $target "mkdir -p $RemoteDir/keys $RemoteDir/deploy $RemoteDir/data"

# --- source: tracked files only -------------------------------------------------
$tmp = Join-Path $env:TEMP "kalshi-src-$PID.tar"
Push-Location $RepoPath
try {
  Write-Host '==> collecting tracked files (git archive)'
  & git archive --format=tar -o $tmp HEAD
  if ($LASTEXITCODE -ne 0) { throw "git archive failed (exit $LASTEXITCODE)" }
  '{0:N1} MB' -f ((Get-Item $tmp).Length / 1MB) | ForEach-Object { Write-Host "    $_" }

  Write-Host '==> uploading'
  & scp -q $tmp "${target}:/tmp/kalshi-src.tar"
  if ($LASTEXITCODE -ne 0) { throw "scp failed (exit $LASTEXITCODE)" }
  ssh $target "tar -xf /tmp/kalshi-src.tar -C $RemoteDir && rm -f /tmp/kalshi-src.tar"

  Write-Host '==> uploading secrets'
  & scp -q (Join-Path $RepoPath 'keys\.env') "${target}:$RemoteDir/keys/.env"
  Get-ChildItem (Join-Path $RepoPath 'keys') -Filter *.pem | ForEach-Object {
    & scp -q $_.FullName "${target}:$RemoteDir/keys/$($_.Name)"
  }
  foreach ($f in @('live.env', 'paper.env', 'proxy.env')) {
    & scp -q (Join-Path $RepoPath "deploy\$f") "${target}:$RemoteDir/deploy/$f"
  }
} finally {
  Pop-Location
  Remove-Item $tmp -ErrorAction SilentlyContinue
}

# --- ownership: the image runs as uid 10001 ('app') -----------------------------
# data/ must be writable by it, or SQLite fails with the misleading
# "unable to open database file: out of memory (14)" -- error 14 is CANTOPEN.
# keys/ and deploy/ stay owned by the shell user (so kalshi.sh's preflight can read
# them) with group 10001 for the container.
Write-Host '==> fixing ownership'
ssh $target @"
sudo chown -R 10001:10001 $RemoteDir/data && sudo chmod 755 $RemoteDir/data
sudo chown -R ${User}:10001 $RemoteDir/keys $RemoteDir/deploy
sudo chmod 750 $RemoteDir/keys $RemoteDir/deploy
sudo chmod 640 $RemoteDir/keys/.env $RemoteDir/keys/*.pem $RemoteDir/deploy/*.env
"@

Write-Host '==> build + restart'
ssh $target 'chmod +x /srv/homeserver/scripts/kalshi.sh 2>/dev/null; /srv/homeserver/scripts/kalshi.sh up'

Write-Host ''
Write-Host '==> dashboard: https://kalshi.<your-domain>   (over WireGuard or on the LAN)'
Write-Host "    logs:      ssh $target '/srv/homeserver/scripts/kalshi.sh logs'"

if ($Logs) { ssh -t $target "/srv/homeserver/scripts/kalshi.sh logs" }
