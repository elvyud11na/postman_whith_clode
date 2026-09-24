<#
.SYNOPSIS
    Runs a Postman collection via Newman with flexible options.

.PARAMETER Collection
    Path to the collection file (.json). Default: postman/collection.json

.PARAMETER Environment
    Path to the environment file (.json). Default: postman/environment.json

.PARAMETER Target
    local - regular local run; opens the Allure report in the browser automatically on success.
    ci    - CI/pipeline run: report is generated but not opened automatically; exits with non-zero code on test failure.

.PARAMETER Report
    allure - build an Allure report (requires newman-reporter-allure and allure-commandline).
    none   - plain Newman console output only, no extra report.

.EXAMPLE
    .\run-tests.ps1
    Local run, no Allure report, default file paths.

.EXAMPLE
    .\run-tests.ps1 -Target local -Report allure
    Local run with Allure report, opens in browser when done.

.EXAMPLE
    .\run-tests.ps1 -Target ci -Report allure
    CI run: report is generated but not opened; non-zero exit code on test failure.
#>

param(
    [string]$Collection = "postman/collection.json",
    [string]$Environment = "postman/environment.json",

    [ValidateSet("local", "ci")]
    [string]$Target = "local",

    [ValidateSet("allure", "none")]
    [string]$Report = "none"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Collection)) {
    Write-Error "Collection file not found: $Collection"
    exit 1
}

if (-not (Test-Path $Environment)) {
    Write-Warning "Environment file not found: $Environment - running without -e"
    $Environment = $null
}

$allureResultsDir = "allure-results"
$allureReportDir  = "allure-report"

Write-Host "=== Newman run ===" -ForegroundColor Cyan
Write-Host "Collection : $Collection"
Write-Host "Environment: $Environment"
Write-Host "Target     : $Target"
Write-Host "Report     : $Report"
Write-Host ""

# Build newman arguments
$newmanArgs = @("run", $Collection)

if ($Environment) {
    $newmanArgs += @("-e", $Environment)
}

if ($Report -eq "allure") {
    if (Test-Path $allureResultsDir) {
        Remove-Item $allureResultsDir -Recurse -Force
    }
    $newmanArgs += @("-r", "cli,allure", "--reporter-allure-export", $allureResultsDir)
} else {
    $newmanArgs += @("-r", "cli")
}

# Write environment info for Allure's Environment widget
function Write-AllureEnvironment {
    if (-not (Test-Path $allureResultsDir)) {
        New-Item -ItemType Directory -Path $allureResultsDir -Force | Out-Null
    }
    $envFile = Join-Path $allureResultsDir "environment.properties"
    @(
        "Target=$Target"
        "Collection=$Collection"
        "Environment.File=$Environment"
        "Run.Date=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    ) | Set-Content -Path $envFile -Encoding UTF8
}

# Run newman
npx newman @newmanArgs
$newmanExitCode = $LASTEXITCODE

Write-Host ""

# Generate Allure report if requested
if ($Report -eq "allure") {
    if (Test-Path $allureResultsDir) {
        Write-AllureEnvironment
        Write-Host "=== Generating Allure report ===" -ForegroundColor Cyan
        allure generate $allureResultsDir -o $allureReportDir --clean

        if ($Target -eq "local") {
            Write-Host "Opening report in browser..." -ForegroundColor Green
            allure open $allureReportDir
        } else {
            Write-Host "Report generated at: $allureReportDir (not opened automatically in CI mode)" -ForegroundColor Yellow
        }
    } else {
        Write-Warning "Allure result data not found - Newman may have failed before generating results."
    }
}

# In CI mode, pass through newman's exit code so failed tests stop the pipeline
if ($Target -eq "ci") {
    exit $newmanExitCode
}

exit 0
