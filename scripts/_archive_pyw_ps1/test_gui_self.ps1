param([switch]$Headless)
$ErrorActionPreference = "Continue"
$projectRoot = "C:\AIS\AI\Prod"
$logFile = "$projectRoot\temp\gui_selftest.log"
New-Item -ItemType Directory -Path "$projectRoot\temp" -Force | Out-Null
$results = @()
$passCount = 0
$failCount = 0

function Test-Result {
    param([string]$Name, [bool]$Ok, [string]$Detail = "")
    $status = if ($Ok) { "PASS" } else { "FAIL" }
    if ($Ok) { $script:passCount++ } else { $script:failCount++ }
    $msg = "[$status] $Name"
    if ($Detail -ne "") { $msg = "$msg -- $Detail" }
    $msg | Out-File $logFile -Append -Encoding UTF8
    $script:results += $msg
}

"=== Test 1: Parser Prod-GUI.ps1 ===" | Out-File $logFile -Append -Encoding UTF8
try {
    $err = $null
    [System.Management.Automation.Language.Parser]::ParseFile("$projectRoot\bin\Prod-GUI.ps1", [ref]$null, [ref]$err)
    Test-Result "Parser Prod-GUI.ps1" ($err.Count -eq 0) "Errors: $($err.Count)"
} catch {
    Test-Result "Parser Prod-GUI.ps1" $false $_.Exception.Message
}

"=== Test 2: Parser Set-MetroTheme.ps1 ===" | Out-File $logFile -Append -Encoding UTF8
try {
    $err = $null
    [System.Management.Automation.Language.Parser]::ParseFile("$projectRoot\scripts\Set-MetroTheme.ps1", [ref]$null, [ref]$err)
    Test-Result "Parser Set-MetroTheme.ps1" ($err.Count -eq 0) "Errors: $($err.Count)"
} catch {
    Test-Result "Parser Set-MetroTheme.ps1" $false $_.Exception.Message
}

"=== Test 3: Parser Save-Snapshot.ps1 ===" | Out-File $logFile -Append -Encoding UTF8
try {
    $err = $null
    [System.Management.Automation.Language.Parser]::ParseFile("$projectRoot\scripts\Save-Snapshot.ps1", [ref]$null, [ref]$err)
    Test-Result "Parser Save-Snapshot.ps1" ($err.Count -eq 0) "Errors: $($err.Count)"
} catch {
    Test-Result "Parser Save-Snapshot.ps1" $false $_.Exception.Message
}

"=== Test 4: UTF-8 BOM encoding ===" | Out-File $logFile -Append -Encoding UTF8
$psFiles = Get-ChildItem "$projectRoot\bin\*.ps1", "$projectRoot\scripts\*.ps1" -Recurse
$bomOk = $true
$bomFails = @()
foreach ($f in $psFiles) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) {
        continue
    }
    $content = [System.IO.File]::ReadAllText($f.FullName)
    $hasCyrillic = $false
    foreach ($ch in $content.ToCharArray()) {
        $code = [int]$ch
        if (($code -ge 1040 -and $code -le 1103) -or $code -eq 1105 -or $code -eq 1025) {
            $hasCyrillic = $true
            break
        }
    }
    if ($hasCyrillic) {
        $bomOk = $false
        $bomFails += $f.Name
    }
}
Test-Result "UTF-8 BOM encoding" $bomOk "No BOM: $($bomFails -join ', ')"

"=== Test 5: MSG style functions ===" | Out-File $logFile -Append -Encoding UTF8
$guiContent = Get-Content "$projectRoot\bin\Prod-GUI.ps1" -Raw -Encoding UTF8
$themeContent = Get-Content "$projectRoot\scripts\Set-MetroTheme.ps1" -Raw -Encoding UTF8
Test-Result "Show-ResultPopup (MSG)" ($guiContent -match 'function Show-ResultPopup')
Test-Result "Show-ValidationErrorWindow (MSG)" ($guiContent -match 'function Show-ValidationErrorWindow')
Test-Result "Show-VssStatusTableWindow (MSG)" ($guiContent -match 'function Show-VssStatusTableWindow')
Test-Result "Show-PbObjectTableWindow (MSG)" ($guiContent -match 'function Show-PbObjectTableWindow')
Test-Result "Show-ProdCompareResult (MSG)" ($guiContent -match 'function Show-ProdCompareResult')
Test-Result "Show-DiffSelectWindow (MSG)" ($guiContent -match 'function Show-DiffSelectWindow')
Test-Result "Show-PbCompareTableWindow (MSG)" ($guiContent -match 'function Show-PbCompareTableWindow')

"=== Test 6: Window ovalness (Border CornerRadius) ===" | Out-File $logFile -Append -Encoding UTF8
    Test-Result "MORDA XAML Border CornerRadius" ($guiContent -match 'CornerRadius="60"')
Test-Result "Apply-GrayWindowStyle exists" ($themeContent -match 'function Apply-GrayWindowStyle')

"=== Test 7: Glossy buttons ===" | Out-File $logFile -Append -Encoding UTF8
Test-Result "Apply-GlossyButtonStyle" ($themeContent -match 'function Apply-GlossyButtonStyle')
Test-Result "Glossy: CornerRadius" ($themeContent -match 'CornerRadius="12"')
Test-Result "Glossy: GradientStop" ($themeContent -match 'GradientStop Color="\$ColorTop"')

"=== Test 8: Gray gradient MSG ===" | Out-File $logFile -Append -Encoding UTF8
Test-Result "GrayWindowStyle: dark top" ($themeContent -match 'FromRgb\(0x80,0x80,0x80\)')
Test-Result "GrayWindowStyle: light center" ($themeContent -match 'FromRgb\(0xD0,0xD0,0xD0\)')

"=== Test 9: GUI operations ===" | Out-File $logFile -Append -Encoding UTF8
$opNames = @(
    "Compare PB",
    "Compare SQL",
    "Compare & Verify",
    "Collect PROD",
    "Export PB",
    "SQL Export",
    "Create RFC",
    "Jira Comment",
    "VSS: Get Latest",
    "VSS: Check Status",
    "VSS: Who Is Using",
    "VSS: Checkout",
    "VSS: Checkin",
    "VSS: Undo",
    "VSS: Object History",
    "Settings",
    "Run Tests"
)
foreach ($op in $opNames) {
    Test-Result "Operation: $op" ($guiContent -match [regex]::Escape($op))
}

"=== Test 10: Config and paths ===" | Out-File $logFile -Append -Encoding UTF8
Test-Result "config.json exists" (Test-Path "$projectRoot\config\config.json")
Test-Result "Logo exists" (Test-Path "$projectRoot\docs\renins_logo.png")
Test-Result "Documentation HTML" (Test-Path "$projectRoot\docs\sql_export_instructions.html")
Test-Result "Documentation PDF" (Test-Path "$projectRoot\docs\sql_export_instructions.pdf")

"=== Test 11: Helper scripts ===" | Out-File $logFile -Append -Encoding UTF8
$scripts = @(
    "Show-Abbreviations.ps1",
    "Show-OpStatus.ps1",
    "Show-Prompts.ps1",
    "VSS-History-Show.ps1",
    "Run-Tests.ps1",
    "Settings-Module.ps1",
    "VSS-Utils.ps1"
)
foreach ($s in $scripts) {
    Test-Result "Script: $s" (Test-Path "$projectRoot\scripts\$s")
}

"=== Test 12: Ovalness all windows ===" | Out-File $logFile -Append -Encoding UTF8
$ovalFiles = @(
    "Save-Snapshot.ps1",
    "Show-Abbreviations.ps1",
    "Show-OpStatus.ps1",
    "Show-Prompts.ps1",
    "VSS-History-Show.ps1"
)
foreach ($f in $ovalFiles) {
    $content = Get-Content "$projectRoot\scripts\$f" -Raw -Encoding UTF8
    Test-Result "Ovalness: $f" ($content -match 'CornerRadius\s*=')
}

"=== Test 13: Built-in progress bars in МОРДА ===" | Out-File $logFile -Append -Encoding UTF8
Test-Result "PbPhase exists" ($guiContent -match 'PbPhase')
Test-Result "PbStep exists" ($guiContent -match 'PbStep')
Test-Result "PbPhaseLabel exists" ($guiContent -match 'PbPhaseLabel')
Test-Result "PbStepLabel exists" ($guiContent -match 'PbStepLabel')
Test-Result "No TaskProgressDialog" ($guiContent -notmatch 'function Show-TaskProgressDialog')

"=== Test 14: No Border.CornerRadius on MetroWindow ===" | Out-File $logFile -Append -Encoding UTF8
$hasBadCornerRadius = $false
$badFiles = @()
$checkFiles = @(
    "$projectRoot\bin\Prod-GUI.ps1",
    "$projectRoot\scripts\Save-Snapshot.ps1",
    "$projectRoot\scripts\Show-Abbreviations.ps1",
    "$projectRoot\scripts\Show-OpStatus.ps1",
    "$projectRoot\scripts\Show-Prompts.ps1",
    "$projectRoot\scripts\VSS-History-Show.ps1"
)
foreach ($cf in $checkFiles) {
    $c = Get-Content $cf -Raw -Encoding UTF8
    if ($c -match '\$window\.Border\.CornerRadius|\$Window\.Border\.CornerRadius|\$selWin\.Border\.CornerRadius') {
        $hasBadCornerRadius = $true
        $badFiles += [System.IO.Path]::GetFileName($cf)
    }
}
Test-Result "No Border.CornerRadius on window" (-not $hasBadCornerRadius) "Bad: $($badFiles -join ', ')"

"" | Out-File $logFile -Append -Encoding UTF8
"=== TOTAL ===" | Out-File $logFile -Append -Encoding UTF8
"Passed: $passCount" | Out-File $logFile -Append -Encoding UTF8
"Failed: $failCount" | Out-File $logFile -Append -Encoding UTF8
"Total: $($passCount + $failCount)" | Out-File $logFile -Append -Encoding UTF8

Write-Host ""
Write-Host "=== MORDA Self-Test Results ===" -ForegroundColor Cyan
foreach ($r in $results) {
    if ($r -match '^\[PASS\]') {
        Write-Host "  $r" -ForegroundColor Green
    } else {
        Write-Host "  $r" -ForegroundColor Red
    }
}
Write-Host ""
Write-Host "Passed: $passCount | Failed: $failCount | Total: $($passCount + $failCount)" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Yellow" })
Write-Host "Log: $logFile" -ForegroundColor Gray

