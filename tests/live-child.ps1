# Live child smoke. Sets GROK_REAL only in this process. Not part of the plugin.
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$script = Join-Path $root "scripts\stop-restyle.ps1"
$real = $env:GROK_REAL
if ([string]::IsNullOrWhiteSpace($real)) { throw "set GROK_REAL for this smoke only" }
$data = Join-Path $env:TEMP ("grok-stop-restyle-live-" + [guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $data -Force | Out-Null
$wall = @"
Managing time is actually just managing focus. Because distractions are everywhere, staying productive takes ruthless boundary-setting. Turn off your notifications and block out your calendar. If you can protect your attention for just two hours a day, your output will easily double. You should also consider how this interacts with a long-running review checklist, and remember that the verify step already runs a named check script. A one-paragraph wall like this should restyle. It does not ask whether to implement anything. The number 17 and the path C:\tmp\restyle-smoke.txt must survive. Extra padding so the source is over six hundred characters.
"@
$ev = @{
    reason               = "end_turn"
    stopHookActive       = $false
    lastAssistantMessage = $wall
} | ConvertTo-Json -Compress
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "pwsh"
foreach ($a in @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $script)) {
    $null = $psi.ArgumentList.Add($a)
}
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$psi.EnvironmentVariables["GROK_PLUGIN_ROOT"] = $root
$psi.EnvironmentVariables["GROK_PLUGIN_DATA"] = $data
$psi.EnvironmentVariables["GROK_REAL"] = $real
$p = New-Object System.Diagnostics.Process
$p.StartInfo = $psi
$null = $p.Start()
$p.StandardInput.Write($ev)
$p.StandardInput.Close()
$out = $p.StandardOutput.ReadToEnd()
$err = $p.StandardError.ReadToEnd()
if (-not $p.WaitForExit(55000)) {
    try { $p.Kill($true) } catch { }
    throw "live hook timed out"
}
Write-Host "exit=$($p.ExitCode)"
if ($err) { Write-Host "stderr=$err" }
Write-Host "stdout=$out"
if ($p.ExitCode -ne 0) { exit 1 }
if ($out -match "Hard wrap" -or $out -match "# Restyle only") { throw "spec leaked" }
$j = $out | ConvertFrom-Json
$ctx = [string]$j.hookSpecificOutput.additionalContext
$prefix = "Output the following text verbatim as your user-facing reply. No preamble."
if (-not $ctx.StartsWith($prefix)) { throw "missing prefix" }
$body = $ctx.Substring($prefix.Length).Trim()
if ($body.StartsWith($prefix)) { throw "doubled prefix" }
if ($body -notmatch "17") { throw "dropped number 17" }
if ($body -notmatch "restyle-smoke") { throw "dropped path" }
Write-Host "live-child ok"
exit 0
