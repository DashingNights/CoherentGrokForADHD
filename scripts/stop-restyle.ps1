# Stop hook: restyle lastAssistantMessage in a child Grok process.
# Fail open. Never print prompt.md (the restyle spec) to stdout.
#
# Child binary: GROK_REAL if set, else PATH grok (stock).
# If PATH grok is a shim that injects --system-prompt-override or re-fires Stop,
# set GROK_REAL to the unwrapped binary and keep the isolated child home.

$ErrorActionPreference = "Stop"
$MaxSourceChars = 9000
$MinSourceChars = 80
$MaxContextChars = 9800
$ChildTimeoutMs = 40000
$VerbatimPrefix = "Output the following text verbatim as your user-facing reply. No preamble."

function Allow-Stop {
    exit 0
}

function Get-PluginRoot {
    if (-not [string]::IsNullOrWhiteSpace($env:GROK_PLUGIN_ROOT)) {
        return $env:GROK_PLUGIN_ROOT.TrimEnd("\", "/")
    }
    if ($PSScriptRoot) {
        $sibling = Join-Path $PSScriptRoot "..\prompt.md"
        if (Test-Path -LiteralPath $sibling) {
            return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path.TrimEnd("\", "/")
        }
        $flat = Join-Path $PSScriptRoot "prompt.md"
        if (Test-Path -LiteralPath $flat) {
            return $PSScriptRoot.TrimEnd("\", "/")
        }
        return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path.TrimEnd("\", "/")
    }
    return (Get-Location).ProviderPath.TrimEnd("\", "/")
}

function Get-DataDir {
    if (-not [string]::IsNullOrWhiteSpace($env:GROK_PLUGIN_DATA)) {
        return $env:GROK_PLUGIN_DATA.TrimEnd("\", "/")
    }
    $tmp = [System.IO.Path]::GetTempPath()
    return (Join-Path $tmp "grok-stop-restyle").TrimEnd("\", "/")
}

function Get-ParentGrokHome {
    if (-not [string]::IsNullOrWhiteSpace($env:GROK_HOME)) {
        return $env:GROK_HOME.TrimEnd("\", "/")
    }
    if ($env:USERPROFILE) {
        return (Join-Path $env:USERPROFILE ".grok").TrimEnd("\", "/")
    }
    if ($env:HOME) {
        return (Join-Path $env:HOME ".grok").TrimEnd("\", "/")
    }
    return $null
}

function Get-GrokBinary {
    if (-not [string]::IsNullOrWhiteSpace($env:GROK_REAL)) {
        return $env:GROK_REAL
    }
    $cmd = Get-Command grok -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandType -eq "Application" } |
        Select-Object -First 1
    if ($cmd -and $cmd.Source) { return [string]$cmd.Source }
    return $null
}

function Test-SamePath([string]$a, [string]$b) {
    if ([string]::IsNullOrWhiteSpace($a) -or [string]::IsNullOrWhiteSpace($b)) { return $false }
    $na = $a.TrimEnd("\", "/")
    $nb = $b.TrimEnd("\", "/")
    return [string]::Equals($na, $nb, [StringComparison]::OrdinalIgnoreCase)
}

# Restyle always continues the parent. Skip when regen would not change much.
function Test-AlreadySimple([string]$s) {
    if ($s.Length -lt 600) { return $true }
    $lines = @($s -split '\r?\n' | Where-Object { $_.Trim().Length -gt 0 })
    if ($lines.Count -lt 3) { return $false }
    $short = @($lines | Where-Object { $_.Trim().Length -le 90 }).Count
    if (($short / [double]$lines.Count) -ge 0.7 -and $s.Length -le 2500) { return $true }
    return $false
}

try {
    if ($env:GROK_RESTYLE_CHILD) { Allow-Stop }

    $dataDir = Get-DataDir
    $childHome = Join-Path $dataDir "home"
    $here = (Get-Location).ProviderPath
    if (Test-SamePath $here $childHome) { Allow-Stop }

    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { Allow-Stop }

    $ev = $raw | ConvertFrom-Json
    if ($null -eq $ev) { Allow-Stop }

    if ($ev.subagentType) { Allow-Stop }
    if ($ev.stopHookActive -eq $true) { Allow-Stop }
    if (Test-SamePath ([string]$ev.cwd) $childHome) { Allow-Stop }

    $lock = Join-Path $dataDir ".in-flight"
    if (Test-Path -LiteralPath $lock) {
        $age = (Get-Date) - (Get-Item -LiteralPath $lock).LastWriteTime
        if ($age.TotalSeconds -lt 120) { Allow-Stop }
        Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue
    }

    $reason = [string]$ev.reason
    if ($reason -and $reason -ne "end_turn") { Allow-Stop }

    $source = [string]$ev.lastAssistantMessage
    if ([string]::IsNullOrWhiteSpace($source)) { Allow-Stop }
    if ($source.Length -lt $MinSourceChars) { Allow-Stop }
    if ($source.Length -gt $MaxSourceChars) { Allow-Stop }
    if (Test-AlreadySimple $source) { Allow-Stop }
    $tailLen = [Math]::Min(800, $source.Length)
    $tail = $source.Substring($source.Length - $tailLen)
    if ($tail -match '(?is)(want me to|shall I|should I|need from you).{0,240}\?') { Allow-Stop }

    $pluginRoot = Get-PluginRoot
    $promptPath = Join-Path $pluginRoot "prompt.md"
    if (-not (Test-Path -LiteralPath $promptPath)) {
        $alt = Join-Path $PSScriptRoot "prompt.md"
        if (Test-Path -LiteralPath $alt) { $promptPath = $alt }
    }
    $real = Get-GrokBinary
    if ([string]::IsNullOrWhiteSpace($real)) { Allow-Stop }
    if (-not (Test-Path -LiteralPath $real)) { Allow-Stop }
    if (-not (Test-Path -LiteralPath $promptPath)) { Allow-Stop }

    if (-not (Test-Path -LiteralPath $childHome)) {
        New-Item -ItemType Directory -Path $childHome -Force | Out-Null
    }
    $parentHome = Get-ParentGrokHome
    if ($parentHome) {
        $authSrc = Join-Path $parentHome "auth.json"
        if (Test-Path -LiteralPath $authSrc) {
            Copy-Item -LiteralPath $authSrc -Destination (Join-Path $childHome "auth.json") -Force
        }
    }

    $spec = [System.IO.File]::ReadAllText($promptPath)
    if ([string]::IsNullOrWhiteSpace($spec)) { Allow-Stop }

    $userPrompt = @"
Rewrite the assistant message in <source>.
Keep every number, path, name, and caveat. Shorten only recap and hedging.
Verdict first. One fact per line. Return only the rewritten message.

<source>
$source
</source>
"@
    $promptFile = Join-Path ([System.IO.Path]::GetTempPath()) ("grok-restyle-in-" + [guid]::NewGuid().ToString("n") + ".txt")
    [System.IO.File]::WriteAllText($promptFile, $userPrompt)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $real
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $childHome
    $psi.EnvironmentVariables["GROK_HOME"] = $childHome
    $psi.EnvironmentVariables["GROK_MEMORY"] = "0"
    $psi.EnvironmentVariables["GROK_RESTYLE_CHILD"] = "1"
    foreach ($a in @(
            "--prompt-file", $promptFile,
            "--system-prompt-override", $spec,
            "--effort", "low",
            "--max-turns", "1",
            "--no-subagents",
            "--no-plan",
            "--yolo",
            "--output-format", "json",
            "--cwd", $childHome,
            "--no-auto-update"
        )) {
        $null = $psi.ArgumentList.Add($a)
    }

    [System.IO.File]::WriteAllText($lock, "1")
    $stdout = ""
    $stderr = ""
    $exitCode = -1
    try {
        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi
        $null = $proc.Start()
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()
        if (-not $proc.WaitForExit($ChildTimeoutMs)) {
            try { $proc.Kill($true) } catch { try { $proc.Kill() } catch { } }
            [Console]::Error.WriteLine("restyle child timed out")
            Allow-Stop
        }
        $stdout = $outTask.GetAwaiter().GetResult()
        $stderr = $errTask.GetAwaiter().GetResult()
        $exitCode = $proc.ExitCode
    }
    finally {
        Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $promptFile -Force -ErrorAction SilentlyContinue
    }
    if ($exitCode -ne 0) {
        [Console]::Error.WriteLine("restyle child exit $exitCode")
        if ($stderr) { [Console]::Error.WriteLine($stderr) }
        Allow-Stop
    }
    if ([string]::IsNullOrWhiteSpace($stdout)) { Allow-Stop }

    $out = $stdout | ConvertFrom-Json
    $text = [string]$out.text
    if ([string]::IsNullOrWhiteSpace($text)) { Allow-Stop }
    $text = $text.Trim()
    if ($text.StartsWith($VerbatimPrefix)) {
        $text = $text.Substring($VerbatimPrefix.Length).Trim()
    }
    if ($text.Length -lt 1) { Allow-Stop }
    $ctx = $VerbatimPrefix + "`n`n" + $text
    if ($ctx.Length -gt $MaxContextChars) {
        $ctx = $ctx.Substring(0, $MaxContextChars)
    }

    $payload = @{
        hookSpecificOutput = @{
            hookEventName     = "Stop"
            additionalContext = $ctx
        }
    }
    $json = $payload | ConvertTo-Json -Compress -Depth 6
    [Console]::Out.Write($json)
    exit 0
}
catch {
    [Console]::Error.WriteLine("restyle fail-open: $($_.Exception.Message)")
    exit 0
}
