<#
.SYNOPSIS
    Master test runner for AIS Release Preparation project.
    Runs all registered tests and reports results.
.DESCRIPTION
    Tests:
      1. Parser test — all .ps1 files parse without errors
      2. Encoding test — all .ps1 files with Cyrillic have UTF-8 BOM
      3. Operation fields test — all operations in Prod-GUI.ps1 have valid fields
      4. English text test — no English Write-Host/Read-Host in scripts
      5. Project paths test — critical paths exist
      6. Script syntax test — all scripts can be at least parsed
.PARAMETER Quick
    Run only parser and encoding tests (skip slower checks).
.EXAMPLE
    .\Run-Tests.ps1
.EXAMPLE
    .\Run-Tests.ps1 -Quick
#>

param([switch]$Quick)

$script:rootDir = "C:\AIS\AI\Prod"
$script:passed = 0
$script:failed = 0
$script:results = @()
$script:started = Get-Date
Write-Progress -Activity "Run Tests" -Status "Starting" -PercentComplete 0

function Write-TestResult {
    param([string]$Name, [bool]$Passed, [string]$Detail)
    $status = if ($Passed) { "PASS" } else { "FAIL" }
    $color = if ($Passed) { "Green" } else { "Red" }
    Write-Host ("[{0,-4}] {1,-55} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
    if ($Passed) { $script:passed++ } else { $script:failed++ }
    $script:results += @{ Name = $Name; Passed = $Passed; Detail = $Detail }
}

function Test-AllParsers {
    Write-Host "`n=== Test 1: Parser validation ===" -ForegroundColor Cyan
    $files = @(
        "$script:rootDir\bin\Prod-GUI.ps1",
        "$script:rootDir\scripts\Compare-Export.ps1",
        "$script:rootDir\scripts\Compare-PB.ps1",
        "$script:rootDir\scripts\Compare-SQL.ps1",
        "$script:rootDir\scripts\Create-RFC.ps1",
        "$script:rootDir\scripts\Find-JiraFields.ps1",
        "$script:rootDir\scripts\Add-ReleaseComment.ps1",
        "$script:rootDir\scripts\AIS_export.ps1",
        "$script:rootDir\scripts\Initialize-Project.ps1",
        "$script:rootDir\scripts\Settings-Module.ps1",
        "$script:rootDir\scripts\VSS-Utils.ps1",
        "$script:rootDir\scripts\VSS-History.ps1",
        "$script:rootDir\scripts\VSS-History-Show.ps1",
        "$script:rootDir\scripts\Set-MetroTheme.ps1",
        "$script:rootDir\scripts\Show-Abbreviations.ps1",
        "$script:rootDir\scripts\Show-Prompts.ps1",
        "$script:rootDir\scripts\Run-Tests.ps1",
        "$script:rootDir\scripts\Test-MetroTheme.ps1",
        "$script:rootDir\scripts\Test-VssEncoding.ps1",
        "$script:rootDir\scripts\Run-FixCycle.ps1",
        "$script:rootDir\scripts\auto_fix_loop.ps1",
        "$script:rootDir\scripts\test_sql_export.ps1",
        "$script:rootDir\scripts\test_gui_params.ps1"
    ) | Select-Object -Unique
    $allOk = $true
    foreach ($f in $files) {
        if (-not (Test-Path $f)) { Write-TestResult "Parser: $(Split-Path $f -Leaf)" $false "NOT FOUND"; $allOk = $false; continue }
        $err = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$err)
        if ($err) {
            $msg = ($err | ForEach-Object { "$($_.Extent.StartLineNumber): $($_.Message)" }) -join "; "
            Write-TestResult "Parser: $(Split-Path $f -Leaf)" $false $msg
            $allOk = $false
        } else {
            Write-TestResult "Parser: $(Split-Path $f -Leaf)" $true "OK"
        }
    }
    return $allOk
}

function Test-AllEncodings {
    Write-Host "`n=== Test 2: Encoding (UTF-8 BOM) ===" -ForegroundColor Cyan
    $files = Get-ChildItem "$script:rootDir\bin\*.ps1", "$script:rootDir\scripts\*.ps1" -File
    $allOk = $true
    foreach ($f in $files) {
        $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        $hasCyrillic = $false
        foreach ($c in $text.ToCharArray()) { if ($c -ge 0x0400 -and $c -le 0x04FF) { $hasCyrillic = $true; break } }
        if ($hasCyrillic -and -not $hasBom) {
            Write-TestResult "Encoding: $($f.Name)" $false "Cyrillic without BOM"
            $allOk = $false
        } elseif (-not $hasCyrillic -and $hasBom) {
            Write-TestResult "Encoding: $($f.Name)" $true "BOM (no Cyrillic)"
        } elseif ($hasCyrillic -and $hasBom) {
            Write-TestResult "Encoding: $($f.Name)" $true "OK (BOM + Cyrillic)"
        } else {
            Write-TestResult "Encoding: $($f.Name)" $true "OK (ASCII/no BOM)"
        }
    }
    return $allOk
}

function Test-OperationFields {
    Write-Host "`n=== Test 3: Operation fields ===" -ForegroundColor Cyan
    $guiPath = "$script:rootDir\bin\Prod-GUI.ps1"
    if (-not (Test-Path $guiPath)) { Write-TestResult "Operations" $false "Prod-GUI.ps1 not found"; return $false }

    $content = Get-Content $guiPath -Raw -Encoding UTF8

    # Extract operations by finding blocks with BOTH Name and RusName (excludes field blocks)
    $opsText = $content.Substring($content.IndexOf('$operations = @('))
    $opsText = $opsText.Substring(0, $opsText.IndexOf('"Operations defined:'))
    $rx = [regex]::new('(?m)^(?:[ \t]*@\{|,[ \t]*@\{)')
    $allBlocks = $rx.Split($opsText)
    $opNames = @()
    foreach ($block in $allBlocks) {
        $hasName = $block -match '^\s*Name\s*='
        $hasRusName = $block -match 'RusName\s*='
        if ($hasName -and $hasRusName) {
            if ($block -match '(?<=Name = ")[^"]+') { $opNames += $matches[0] }
        }
    }
    $allOk = $true

    if ($opNames.Count -eq 0) {
        Write-TestResult "Operations" $false "No operations found"
        return $false
    }

    Write-TestResult "Operation count" $true "$($opNames.Count) operations"

    $expectedOps = @(
        'Settings',
        'Run Tests (Run-Tests.ps1)',
        'Export Service',
        'Collect PROD Objects',
        'Export PB: Current or Main',
        'Compare PB: Current and Main',
        'SQL Export',
        'Compare SQL: dev_golden and galaxy',
        'Compare & Verify (Compare-Export.ps1)',
        'Create RFC in Jira',
        'Jira Release Comment',
        'VSS: Get Latest Version',
        'VSS: Check Status',
        'VSS: Who Is Using',
        'VSS: Checkout',
        'VSS: Checkin',
        'VSS: Undo Check Out',
        'VSS: Object History'
    )
    foreach ($exp in $expectedOps) {
        $found = $opNames | Where-Object { $_ -eq $exp }
        if ($found) {
            Write-TestResult "  Has '$exp'" $true "included"
        } else {
            Write-TestResult "  Has '$exp'" $false "NOT FOUND"
            $allOk = $false
        }
    }
    return $allOk
}

function Test-EnglishText {
    Write-Host "`n=== Test 4: English text in scripts ===" -ForegroundColor Cyan
    $allOk = $true
    $dirs = @("$script:rootDir\bin", "$script:rootDir\scripts")
    # Terms that are allowed to start a Write-Host with a capital letter
    $allowedPrefixes = @(
        '===', 'TASK_STATUS', '###VSS_STATUS', '###DIFF_OBJECT', 'RESULT',
        'Parser', 'Encoding', 'Operation', 'Timer', 'Process', 'Timeout',
        'AIS ', 'PB_', 'PBT-', 'SQL_', 'Jira', 'RFC', 'VSS', 'Test',
        'Release:', 'Starting:', 'Please', 'Done', 'TortoiseMerge',
        'Started:', 'Mode:', 'Results:', 'Elapsed:', 'FAIL', 'PASS',
        'Windows-1251', 'ANSICOD', 'Default', 'True', 'False', 'Exit'
    )
    foreach ($dir in $dirs) {
        $files = Get-ChildItem $dir -Filter "*.ps1" -File
        foreach ($f in $files) {
            $content = Get-Content $f.FullName -Raw -Encoding UTF8
            $lines = $content -split "`n"
            $engCount = 0; $firstEng = ""
            foreach ($line in $lines) {
                if ($line -match 'Write-Host\s+"([A-Z_][A-Za-z._/-]*[:.][^"]*)"') {
                    # Technical terms: "Create-RFC.ps1 not found", "PB_Current: 123 files", "Jira: ..."
                    continue
                }
                if ($line -match 'Write-Host\s+"([A-Z][^"]*)"') {
                    $text = $matches[1]
                    $isAllowed = $false
                    foreach ($prefix in $allowedPrefixes) {
                        if ($text -match "^$prefix") { $isAllowed = $true; break }
                    }
                    if (-not $isAllowed) {
                        $engCount++
                        if (-not $firstEng) { $firstEng = $text }
                    }
                }
            }
            if ($engCount -gt 0) {
                Write-TestResult "English: $($f.Name)" $false "$engCount eng: $firstEng"
                $allOk = $false
            }
        }
    }
    if ($allOk) { Write-TestResult "English text" $true "All scripts use Russian" }
    return $allOk
}

function Test-ProjectPaths {
    Write-Host "`n=== Test 5: Project paths ===" -ForegroundColor Cyan
    $allOk = $true
    $paths = @(
        @{ Path = "$script:rootDir\config\config.json"; Label = "config.json" }
        @{ Path = "$script:rootDir\docs\renins_logo.png"; Label = "Logo" }
        @{ Path = "$script:rootDir\docs\sql_export_instructions.html"; Label = "HTML docs" }
        @{ Path = "$script:rootDir\bin\Prod-GUI.bat"; Label = "Prod-GUI.bat" }
    )
    foreach ($p in $paths) {
        if (Test-Path $p.Path) {
            Write-TestResult "  $($p.Label)" $true "OK"
        } else {
            Write-TestResult "  $($p.Label)" $false "NOT FOUND: $($p.Path)"
            $allOk = $false
        }
    }
    return $allOk
}

function Test-OptionalParams {
    Write-Host "`n=== Test 6: Optional/required parameters ===" -ForegroundColor Cyan
    $guiPath = "$script:rootDir\bin\Prod-GUI.ps1"
    $content = Get-Content $guiPath -Raw -Encoding UTF8
    $allOk = $true

    # Extract operations: find blocks with BOTH Name and RusName (excludes field blocks)
    $opsText = $content.Substring($content.IndexOf('$operations = @('))
    $opsText = $opsText.Substring(0, $opsText.IndexOf('"Operations defined:'))
    $rx = [regex]::new('(?m)^(?:[ \t]*@\{|,[ \t]*@\{)')
    $allBlocks = $rx.Split($opsText)
    $ops = @()
    foreach ($block in $allBlocks) {
        if ($block -match 'RusName\s*=') { $ops += $block }
    }
    
    # Expected TaskName requirements
    $taskNameOptional = @('Export PB: Current or Main', 'Compare PB: Current and Main', 'SQL Export',
                         'Compare SQL: dev_golden and galaxy', 'Compare & Verify (Compare-Export.ps1)',
                         'VSS: Get Latest Version', 'VSS: Check Status', 'VSS: Who Is Using',
                         'VSS: Checkout', 'VSS: Checkin', 'VSS: Undo Check Out', 'VSS: Object History')
    $taskNameRequired = @('Collect PROD Objects', 'Create RFC in Jira', 'Jira Release Comment')

                        foreach ($opBlock in $ops) {
                             $opName = if ($opBlock -match '(?<=Name = ")[^"]+') { $matches[0] } else { continue }
                             $hasTaskName = $opBlock -match 'TaskName'
        
        # Проверка TaskName
        if ($hasTaskName) {
            $isOptional = $false; $isRequired = $false
            foreach ($o in $taskNameOptional) { if ($opName -eq $o -or $opName -like "$o*") { $isOptional = $true; break } }
            foreach ($r in $taskNameRequired) { if ($opName -eq $r -or $opName -like "$r*") { $isRequired = $true; break } }
            
            if ($isOptional) {
                Write-TestResult "  $opName TaskName" $true "optional (no pre-run validation)"
                                 } elseif ($isRequired) {
                                     # Проверяем, что есть валидация в Run handler
                                     $hasValidation = $content -match [regex]::Escape($opName.Substring(0, [Math]::Min(15, $opName.Length))) -and $content -match 'IsNullOrWhiteSpace.*TaskName'
                                     if ($hasValidation) {
                                         Write-TestResult "  $opName TaskName" $true "required + validation OK"
                                     } else {
                                         Write-TestResult "  $opName TaskName" $false "REQUIRED but no pre-run validation"
                                         $allOk = $false
                                     }
            } else {
                Write-TestResult "  $opName TaskName" $false "UNKNOWN status — add to taskNameOptional or taskNameRequired"
                $allOk = $false
            }
        }
        
                             # Проверка Source для SQL Export (по полному тексту, т.к. Fields split)
                             if ($opName -eq 'SQL Export') {
                                 $hasSourceFull = $content -match [regex]::Escape('SQL Export') -and ($content -match 'Name\s*=\s*"Source"')
                                 if ($hasSourceFull) {
                                     Write-TestResult "  $opName Source" $true "field present"
                                 } else {
                                     Write-TestResult "  $opName Source" $false "Source field MISSING"
                                     $allOk = $false
                                 }
                                 # Проверка поля Db для SQL Export
                                 $hasDbFull = $content -match [regex]::Escape('SQL Export') -and ($content -match 'Name\s*=\s*"Db"')
                                 if ($hasDbFull) {
                                     Write-TestResult "  $opName Db" $true "field present"
                                 } else {
                                     Write-TestResult "  $opName Db" $false "Db field MISSING"
                                     $allOk = $false
                                 }
                                 # Проверка что TaskName опционален (нет валидации в батнике)
                                 $batPath = "$script:rootDir\bin\SQL_exp_param.bat"
                                 if (Test-Path $batPath) {
                                     $batContent = Get-Content $batPath -Raw -Encoding UTF8
                                     $taskNameRequired = $batContent -match 'if "%~4"=="" goto usage'
                                     if ($taskNameRequired) {
                                         Write-TestResult "  $opName TaskName optional" $false "BAT requires TaskName (remove check)"
                                         $allOk = $false
                                     } else {
                                         Write-TestResult "  $opName TaskName optional" $true "BAT allows empty TaskName"
                                     }
                                 }
                             }
    }
    return $allOk
}

# ── Main ──
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " AIS Release Preparation — Test Runner" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Started: $($script:started.ToString('yyyy-MM-dd HH:mm:ss'))"
if ($Quick) { Write-Host "Mode: Quick (parser + encoding only)" -ForegroundColor Yellow }
Write-Host ""

if ($Quick) {
    Write-Host "###PHASE###Parser validation|2"
    Write-Host "###PB###Parser validation"
    Test-AllParsers; Write-Host "###STEP###"
    Write-Host "###PHASE###Encoding check|2"
    Write-Host "###PB###Encoding (UTF-8 BOM)"
    Test-AllEncodings; Write-Host "###STEP###"
} else {
    Write-Host "###PHASE###Parser validation|5"
    Write-Host "###PB###Parser validation"
    Test-AllParsers; Write-Host "###STEP###"
    Write-Host "###PHASE###Encoding check|5"
    Write-Host "###PB###Encoding (UTF-8 BOM)"
    Test-AllEncodings; Write-Host "###STEP###"
    Write-Host "###PHASE###Operation fields|5"
    Write-Host "###PB###Operation fields"
    Test-OperationFields; Write-Host "###STEP###"
    Write-Host "###PHASE###English text check|5"
    Write-Host "###PB###English text in scripts"
    Test-EnglishText; Write-Host "###STEP###"
    Write-Host "###PHASE###Project paths|5"
    Write-Host "###PB###Project paths"
    Test-ProjectPaths; Write-Host "###STEP###"
    Write-Host "###PHASE###Optional params|5"
    Write-Host "###PB###Optional params validation"
    Test-OptionalParams; Write-Host "###STEP###"
}

# Summary
Write-Host "###PHASE###Summary|1"
Write-Host "###PB###Results summary"

if ($script:failed -gt 0) { exit 1 } else { exit 0 }
