# Loom Testing Edition PowerShell shell integration.
# Writes JSONL command records to %LOCALAPPDATA%\Loom Testing Edition\history.jsonl.
# Mirrors the macOS zsh shim in Loom/Terminal/CommandHistoryService.swift.

$loomDir = Join-Path $env:LOCALAPPDATA 'Loom Testing Edition'
if (-not (Test-Path $loomDir)) { New-Item -ItemType Directory -Force -Path $loomDir | Out-Null }
$loomHistoryPath = Join-Path $loomDir 'history.jsonl'
$loomOutputDir = Join-Path $loomDir 'output'
if (-not (Test-Path $loomOutputDir)) { New-Item -ItemType Directory -Force -Path $loomOutputDir | Out-Null }

$global:__LoomLastCommand = $null
$global:__LoomLastStart = $null

function Test-LoomSecretCommand {
  param([string]$Command)
  if ([string]::IsNullOrWhiteSpace($Command)) { return $true }
  $lower = $Command.ToLowerInvariant()
  $prefixes = @(
    'gh auth',
    'npm token',
    'ssh-add',
    'aws configure',
    'docker login',
    'gcloud auth',
    'az login',
    'pass '
  )
  foreach ($prefix in $prefixes) {
    if ($lower.StartsWith($prefix)) { return $true }
  }
  if ($Command -match '(?i)(^|[;&|\s])(export\s+)?[A-Z_][A-Z0-9_]*(KEY|TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL)[A-Z0-9_]*=') { return $true }
  if ($lower.Contains('--password') -or $lower.Contains('--token') -or $lower.Contains('--api-key') -or $lower.Contains('authorization: bearer')) { return $true }
  return $false
}

function ConvertTo-LoomRedactedCommand {
  param([string]$Command)
  $value = $Command
  $value = [regex]::Replace($value, '(?i)(authorization:\s*bearer\s+)[A-Za-z0-9._~+/\-]+=*', '$1[REDACTED]')
  $value = [regex]::Replace($value, '(?i)(--(?:api-key|token|password|secret)(?:=|\s+))([^\s"''`]+)', '$1[REDACTED]')
  $value = [regex]::Replace($value, '(?i)\b(api[_-]?key|token|secret|password|passwd|credential)(\s*[:=]\s*)(["'']?)([^\s"''`]+)', '$1$2$3[REDACTED]')
  $value = [regex]::Replace($value, '\bsk-[A-Za-z0-9]{12,}\b', '[REDACTED_OPENAI_KEY]')
  $value = [regex]::Replace($value, '\bgh[pousr]_[A-Za-z0-9_]{20,}\b', '[REDACTED_GITHUB_TOKEN]')
  return $value
}

Set-PSReadLineOption -AddToHistoryHandler {
  param($line)
  if (Test-LoomSecretCommand $line) { return $false }
  $global:__LoomLastCommand = $line
  $global:__LoomLastStart = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  return $true
}

function Invoke-LoomRecord {
  param(
    [string]$Command,
    [long]$StartMs,
    [int]$ExitCode,
    [string]$Cwd,
    [string]$Shell
  )
  if ([string]::IsNullOrWhiteSpace($Command)) { return }
  if (Test-LoomSecretCommand $Command) { return }
  $endMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $record = [ordered]@{
    id        = [guid]::NewGuid().ToString()
    command   = (ConvertTo-LoomRedactedCommand $Command)
    cwd       = $Cwd
    shell     = $Shell
    exitCode  = $ExitCode
    startedAt = $StartMs
    endedAt   = $endMs
    durationMs= ($endMs - $StartMs)
  }
  $json = $record | ConvertTo-Json -Compress
  Add-Content -Path $loomHistoryPath -Value $json -Encoding utf8
}

$global:__loomPromptOriginal = (Get-Item function:prompt).Definition

function global:prompt {
  $exit = $LASTEXITCODE
  if ($global:__LoomLastCommand -and $global:__LoomLastStart) {
    Invoke-LoomRecord -Command $global:__LoomLastCommand -StartMs $global:__LoomLastStart -ExitCode $exit -Cwd (Get-Location).Path -Shell 'pwsh'
    $global:__LoomLastCommand = $null
    $global:__LoomLastStart = $null
  }
  & ([ScriptBlock]::Create($global:__loomPromptOriginal))
}

function Invoke-LoomCapture {
  param([Parameter(Mandatory)][string]$Command)
  if (Test-LoomSecretCommand $Command) { return }
  $id = [guid]::NewGuid().ToString()
  $outFile = Join-Path $loomOutputDir "$id.out"
  $start = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  & cmd /c $Command 2>&1 | Tee-Object -FilePath $outFile
  $exit = $LASTEXITCODE
  $end = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $record = [ordered]@{
    id         = $id
    command    = (ConvertTo-LoomRedactedCommand $Command)
    cwd        = (Get-Location).Path
    shell      = 'pwsh'
    exitCode   = $exit
    startedAt  = $start
    endedAt    = $end
    durationMs = ($end - $start)
    outputPath = $outFile
  }
  $json = $record | ConvertTo-Json -Compress
  Add-Content -Path $loomHistoryPath -Value $json -Encoding utf8
}
