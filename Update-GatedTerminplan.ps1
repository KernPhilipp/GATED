$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$terminplanPath = Join-Path $scriptDir 'GATED-Terminplan.txt'

if (-not (Test-Path -LiteralPath $terminplanPath)) {
    throw "Datei nicht gefunden: $terminplanPath"
}

$lines = Get-Content -LiteralPath $terminplanPath

if ($lines.Count -lt 4) {
    throw 'GATED-Terminplan.txt hat weniger als 4 Zeilen.'
}

$today = (Get-Date).Date
$targetDate = (Get-Date '2026-05-18').Date
$remainingDays = ($targetDate - $today).Days

if ($remainingDays -lt 0) {
    $remainingDays = 0
}

$lines[3] = "Noch $remainingDays Tage bis 18. Mai 2026"

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllLines($terminplanPath, $lines, $utf8NoBom)

Write-Output $lines[3]
