[CmdletBinding()]
param(
    [string]$GodotPath = "D:\Programs\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe",
    [switch]$SkipRealtime,
    [string]$OutputRoot = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot ".artifacts\p2-validation"
}
$runDirectory = Join-Path $OutputRoot (Get-Date -Format "yyyyMMdd-HHmmss")
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null

if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot executable not found: $GodotPath"
}

function Convert-ToArgumentString {
    param([string[]]$Arguments)
    $quoted = foreach ($argument in $Arguments) {
        if ($argument -match '[\s"]') {
            '"' + ($argument -replace '"', '\"') + '"'
        } else {
            $argument
        }
    }
    return ($quoted -join " ")
}

function Invoke-ValidationProcess {
    param(
        [string]$Name,
        [string]$Kind,
        [string]$Executable,
        [string[]]$Arguments,
        [int]$TimeoutSeconds,
        [bool]$ShowWindow = $false,
        [string]$ExpectedOutputPattern = "",
        [string]$RejectedOutputPattern = '(?im)SCRIPT ERROR:|Parse Error:|Failed to load script'
    )

    $safeName = $Name -replace '[^A-Za-z0-9_.-]', '_'
    $logPath = Join-Path $runDirectory ($safeName + ".log")
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $timedOut = $false
    $exitCode = -1
    $stdout = ""
    $stderr = ""
    $status = "failed"

    try {
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $Executable
        $startInfo.Arguments = Convert-ToArgumentString $Arguments
        $startInfo.WorkingDirectory = $repoRoot
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = -not $ShowWindow
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        if (-not $process.Start()) {
            throw "Process failed to start"
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $timedOut = $true
            $process.Kill()
            $process.WaitForExit()
        }
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
        if (-not $timedOut) {
            $exitCode = $process.ExitCode
        }
        $status = if ($timedOut) { "timeout" } elseif ($exitCode -eq 0) { "passed" } else { "failed" }
        if ($status -eq "passed" -and -not [string]::IsNullOrWhiteSpace($ExpectedOutputPattern) -and $stdout -notmatch $ExpectedOutputPattern) {
            $status = "failed"
            $stderr += "Expected output pattern was not found: $ExpectedOutputPattern"
        }
        if ($status -eq "passed" -and -not [string]::IsNullOrWhiteSpace($RejectedOutputPattern) -and ($stdout + $stderr) -match $RejectedOutputPattern) {
            $status = "failed"
            $stderr += "Rejected output pattern was found: $RejectedOutputPattern"
        }
    } catch {
        $stderr = ($_ | Out-String)
        $status = "failed"
    } finally {
        $stopwatch.Stop()
    }

    $command = '"' + $Executable + '" ' + (Convert-ToArgumentString $Arguments)
    $log = @(
        "COMMAND: $command",
        "STATUS: $status",
        "EXIT_CODE: $exitCode",
        "TIMED_OUT: $timedOut",
        "DURATION_SECONDS: $([Math]::Round($stopwatch.Elapsed.TotalSeconds, 3))",
        "",
        "===== STDOUT =====",
        $stdout,
        "===== STDERR =====",
        $stderr
    ) -join [Environment]::NewLine
    Set-Content -LiteralPath $logPath -Value $log -Encoding UTF8

    return [PSCustomObject][ordered]@{
        name = $Name
        kind = $Kind
        status = $status
        exit_code = $exitCode
        timed_out = $timedOut
        duration_seconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
        log_path = $logPath
        command = $command
    }
}

function Add-SkippedResult {
    param([string]$Name, [string]$Kind, [string]$Reason)
    return [PSCustomObject][ordered]@{
        name = $Name
        kind = $Kind
        status = "skipped"
        exit_code = $null
        timed_out = $false
        duration_seconds = 0
        log_path = $null
        command = $null
        reason = $Reason
    }
}

$results = New-Object System.Collections.Generic.List[object]
$commonHeadless = @("--headless", "--rendering-method", "gl_compatibility", "--path", $repoRoot)

$results.Add((Invoke-ValidationProcess -Name "godot-version" -Kind "environment" -Executable $GodotPath -Arguments @("--version") -TimeoutSeconds 30 -ExpectedOutputPattern '(?m)^4\.7')) | Out-Null
$results.Add((Invoke-ValidationProcess -Name "script-scan" -Kind "headless" -Executable $GodotPath -Arguments ($commonHeadless + @("--editor", "--quit")) -TimeoutSeconds 180)) | Out-Null
$results.Add((Invoke-ValidationProcess -Name "main-scene-smoke" -Kind "headless" -Executable $GodotPath -Arguments ($commonHeadless + @("--quit-after", "2")) -TimeoutSeconds 90)) | Out-Null

$realtimeScene = "MapTravelRealtimeAcceptance.tscn"
$testScenes = Get-ChildItem -LiteralPath (Join-Path $repoRoot "tests") -Filter "*.tscn" -File |
    Where-Object { $_.Name -ne $realtimeScene } |
    Sort-Object Name
foreach ($scene in $testScenes) {
    $resourcePath = "res://tests/" + $scene.Name
    $results.Add((Invoke-ValidationProcess -Name $scene.BaseName -Kind "contract" -Executable $GodotPath -Arguments ($commonHeadless + @($resourcePath)) -TimeoutSeconds 240)) | Out-Null
}

$headlessFailures = @($results | Where-Object { $_.kind -in @("environment", "headless", "contract") -and $_.status -ne "passed" })
if ($SkipRealtime) {
    $results.Add((Add-SkippedResult -Name "MapTravelRealtimeAcceptance" -Kind "realtime" -Reason "Skipped by -SkipRealtime")) | Out-Null
} elseif ($headlessFailures.Count -gt 0) {
    $results.Add((Add-SkippedResult -Name "MapTravelRealtimeAcceptance" -Kind "realtime" -Reason "Skipped because a prerequisite headless check failed")) | Out-Null
} else {
    $realtimeArgs = @("--rendering-method", "gl_compatibility", "--path", $repoRoot, "res://tests/$realtimeScene")
    $results.Add((Invoke-ValidationProcess -Name "MapTravelRealtimeAcceptance" -Kind "realtime" -Executable $GodotPath -Arguments $realtimeArgs -TimeoutSeconds 120 -ShowWindow $true)) | Out-Null
}

$results.Add((Invoke-ValidationProcess -Name "git-diff-check" -Kind "repository" -Executable "git" -Arguments @("diff", "--check") -TimeoutSeconds 30)) | Out-Null

$resultArray = @($results)
$failed = @($resultArray | Where-Object { $_.status -in @("failed", "timeout") })
$passed = @($resultArray | Where-Object { $_.status -eq "passed" })
$skipped = @($resultArray | Where-Object { $_.status -eq "skipped" })
$summary = [PSCustomObject][ordered]@{
    schema_version = 1
    generated_at = (Get-Date).ToString("o")
    repository = $repoRoot
    godot_path = $GodotPath
    overall_status = if ($failed.Count -eq 0 -and $skipped.Count -eq 0) { "passed" } elseif ($failed.Count -gt 0) { "failed" } else { "incomplete" }
    counts = [PSCustomObject][ordered]@{
        passed = $passed.Count
        failed = $failed.Count
        skipped = $skipped.Count
        total = $resultArray.Count
    }
    results = $resultArray
}
$summaryPath = Join-Path $runDirectory "summary.json"
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Host "P2 validation: $($summary.overall_status)"
Write-Host "Passed: $($passed.Count), Failed/timeout: $($failed.Count), Skipped: $($skipped.Count)"
Write-Host "Summary: $summaryPath"
foreach ($failure in $failed) {
    Write-Host "FAILED: $($failure.name) -> $($failure.log_path)"
}

if ($failed.Count -gt 0 -or $skipped.Count -gt 0) {
    exit 1
}
exit 0
