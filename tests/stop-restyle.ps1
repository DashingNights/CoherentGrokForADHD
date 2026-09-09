# Unit tests for stop-restyle.ps1 skip/prefix contract. Not shipped as a plugin skill.
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$script = Join-Path $root "scripts\stop-restyle.ps1"
$fail = 0
$n = 0

function Invoke-Hook([string]$json, [hashtable]$extraEnv) {
    $tmpIn = Join-Path $env:TEMP ("restyle-test-in-" + [guid]::NewGuid().ToString("n") + ".json")
    [System.IO.File]::WriteAllText($tmpIn, $json)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "pwsh"
    $psi.ArgumentList.Add("-NoProfile") | Out-Null
    $psi.ArgumentList.Add("-ExecutionPolicy") | Out-Null
    $psi.ArgumentList.Add("Bypass") | Out-Null
    $psi.ArgumentList.Add("-File") | Out-Null
    $psi.ArgumentList.Add($script) | Out-Null
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables["GROK_PLUGIN_ROOT"] = $root
    $psi.EnvironmentVariables["GROK_PLUGIN_DATA"] = (Join-Path $env:TEMP "grok-stop-restyle-test-data")
    if ($extraEnv) {
        foreach ($k in $extraEnv.Keys) { $psi.EnvironmentVariables[$k] = [string]$extraEnv[$k] }
    }
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    $null = $p.Start()
    $p.StandardInput.Write([System.IO.File]::ReadAllText($tmpIn))
    $p.StandardInput.Close()
    $out = $p.StandardOutput.ReadToEnd()
    $err = $p.StandardError.ReadToEnd()
    $p.WaitForExit(15000) | Out-Null
    Remove-Item -LiteralPath $tmpIn -Force -ErrorAction SilentlyContinue
    return @{ Exit = $p.ExitCode; Out = $out; Err = $err }
}

function Assert-Allow([string]$name, $r) {
    $script:n++
    if ($r.Exit -ne 0) {
        Write-Host "FAIL $name exit $($r.Exit) err=$($r.Err)"
        $script:fail++
        return
    }
    if ($r.Out -match "prompt.md" -or $r.Out -match "Hard wrap" -or $r.Out -match "Restyle only") {
        Write-Host "FAIL $name leaked spec to stdout"
        $script:fail++
        return
    }
    if (-not [string]::IsNullOrWhiteSpace($r.Out)) {
        Write-Host "FAIL $name expected empty stdout, got: $($r.Out)"
        $script:fail++
        return
    }
    Write-Host "ok   $name"
}

function Assert-Restyle([string]$name, $r) {
    $script:n++
    if ($r.Exit -ne 0) {
        Write-Host "FAIL $name exit $($r.Exit) err=$($r.Err)"
        $script:fail++
        return
    }
    if ($r.Out -match "Hard wrap" -or $r.Out -match "# Restyle only") {
        Write-Host "FAIL $name leaked spec"
        $script:fail++
        return
    }
    try { $j = $r.Out | ConvertFrom-Json } catch {
        Write-Host "FAIL $name not json: $($r.Out)"
        $script:fail++
        return
    }
    $ctx = [string]$j.hookSpecificOutput.additionalContext
    $prefix = "Output the following text verbatim as your user-facing reply. No preamble."
    if (-not $ctx.StartsWith($prefix)) {
        Write-Host "FAIL $name missing prefix: $ctx"
        $script:fail++
        return
    }
    $rest = $ctx.Substring($prefix.Length).Trim()
    if ($rest.StartsWith($prefix)) {
        Write-Host "FAIL $name doubled prefix"
        $script:fail++
        return
    }
    if ($rest -notmatch "42") {
        Write-Host "FAIL $name rewrite body missing: $ctx"
        $script:fail++
        return
    }
    Write-Host "ok   $name"
}

$end = @{ reason = "end_turn"; stopHookActive = $false; lastAssistantMessage = "short" }
Assert-Allow "child-env" (Invoke-Hook '{"reason":"end_turn"}' @{ GROK_RESTYLE_CHILD = "1" })
Assert-Allow "too-short" (Invoke-Hook (@{ reason = "end_turn"; lastAssistantMessage = ("x" * 40) } | ConvertTo-Json -Compress) $null)
Assert-Allow "already-simple" (Invoke-Hook (@{ reason = "end_turn"; lastAssistantMessage = ("clean line. " * 20) } | ConvertTo-Json -Compress) $null)

$ask = @"
This paragraph is long enough that a naive length check would restyle it, but the close asks whether to implement the change so the hook must allow stop instead of injecting a rewrite that looks like a go-ahead. filler filler filler filler filler filler filler filler filler filler filler.
Want me to implement that?
"@
Assert-Allow "implement-ask" (Invoke-Hook (@{ reason = "end_turn"; lastAssistantMessage = $ask } | ConvertTo-Json -Compress) $null)
Assert-Allow "stopHookActive" (Invoke-Hook (@{ reason = "end_turn"; stopHookActive = $true; lastAssistantMessage = ("w" * 900) } | ConvertTo-Json -Compress) $null)
Assert-Allow "subagent" (Invoke-Hook (@{ reason = "end_turn"; subagentType = "explore"; lastAssistantMessage = ("w" * 900) } | ConvertTo-Json -Compress) $null)
Assert-Allow "not-end-turn" (Invoke-Hook (@{ reason = "shutdown"; lastAssistantMessage = ("w" * 900) } | ConvertTo-Json -Compress) $null)

$fakeDir = Join-Path $env:TEMP ("grok-fake-" + [guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $fakeDir -Force | Out-Null
$fakeExe = Join-Path $fakeDir "grok-fake.exe"
$csFile = Join-Path $fakeDir "grok-fake.cs"
@'
using System;
class P {
  static int Main(string[] args) {
    string t = "Output the following text verbatim as your user-facing reply. No preamble.\n\nKept path C:\\tmp\\x and the number 42.";
    string json = "{\"text\":\"" + t.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\n", "\\n") + "\"}";
    Console.Out.Write(json);
    return 0;
  }
}
'@ | Set-Content -LiteralPath $csFile -Encoding ASCII
$csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path -LiteralPath $csc)) {
    $csc = Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe"
}
& $csc /nologo /out:$fakeExe $csFile | Out-Host
if (-not (Test-Path -LiteralPath $fakeExe)) { throw "failed to build grok-fake.exe" }

$wall = ("Managing time is actually just managing focus. Distractions are everywhere, so staying productive takes ruthless boundary-setting. Turn off notifications and block the calendar. Protect attention for two hours a day and output doubles. " * 4)
$ev = @{
    reason               = "end_turn"
    stopHookActive       = $false
    lastAssistantMessage = $wall
} | ConvertTo-Json -Compress
Assert-Restyle "wall-prefix" (Invoke-Hook $ev @{ GROK_REAL = $fakeExe })

# already-clean short lines (3+ lines, 70% short, <=2500)
$clean = (1..20 | ForEach-Object { "This is a short verdict line number $_ and some padding words." }) -join "`n"
Assert-Allow "short-lines" (Invoke-Hook (@{ reason = "end_turn"; lastAssistantMessage = $clean } | ConvertTo-Json -Compress) $null)

Write-Host "---"
Write-Host "$n tests, $fail failed"
if ($fail -gt 0) { exit 1 }
exit 0
