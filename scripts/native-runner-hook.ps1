$ErrorActionPreference = 'Stop'
$taskHookAccepted = $false

try {
  & 'C:\Program Files\nodejs\node.exe' `
    (Join-Path $PSScriptRoot 'hook.mjs') `
    (Join-Path $PSScriptRoot 'guard.mjs') `
    (Join-Path $PSScriptRoot 'binding.json') 2>$null
  $taskHookAccepted = $LASTEXITCODE -eq 0
} catch {
  $taskHookAccepted = $false
}

if (-not $taskHookAccepted) {
  [Console]::Error.Write("Native runner binding refused: RUNNER_UNTRUSTED.`n")
  [Environment]::Exit(1)
}

exit 0
