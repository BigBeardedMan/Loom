# Loom PowerShell shell integration.
# Writes JSONL command records to %LOCALAPPDATA%\Loom\history.jsonl.
# Mirrors the macOS zsh shim in Loom/Terminal/CommandHistoryService.swift.

$loomDir = Join-Path $env:LOCALAPPDATA 'Loom'
if (-not (Test-Path $loomDir)) { New-Item -ItemType Directory -Force -Path $loomDir | Out-Null }
$loomHistoryPath = Join-Path $loomDir 'history.jsonl'
$loomOutputDir = Join-Path $loomDir 'output'
if (-not (Test-Path $loomOutputDir)) { New-Item -ItemType Directory -Force -Path $loomOutputDir | Out-Null }

$global:__LoomLastCommand = $null
$global:__LoomLastStart = $null

Set-PSReadLineOption -AddToHistoryHandler {
  param($line)
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
  $endMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $record = [ordered]@{
    id        = [guid]::NewGuid().ToString()
    command   = $Command
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
  $id = [guid]::NewGuid().ToString()
  $outFile = Join-Path $loomOutputDir "$id.out"
  $start = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  & cmd /c $Command 2>&1 | Tee-Object -FilePath $outFile
  $exit = $LASTEXITCODE
  $end = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $record = [ordered]@{
    id         = $id
    command    = $Command
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
