<#
.SYNOPSIS
    Automated test for Prod-GUI.ps1
.DESCRIPTION
    Launches GUI, fills fields, clicks Run, and captures output
#>

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName System.Windows.Forms

# Launch GUI in background
Write-Host "Launching GUI..."
$guiProcess = Start-Process -FilePath "powershell.exe" `
    -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File C:\AIS\AI\Prod\bin\Prod-GUI.ps1" `
    -PassThru

Start-Sleep -Seconds 3

# Get main window
$root = [System.Windows.Automation.AutomationElement]::RootElement
$condition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::NameProperty,
    "AIS Release Preparation"
)
$window = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $condition)

if ($null -eq $window) {
    Write-Host "ERROR: GUI window not found"
    $guiProcess.Kill()
    exit 1
}

Write-Host "GUI window found"

# Helper function to find control by AutomationId
function Find-Control {
    param($parent, $automationId)
    $condition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty,
        $automationId
    )
    return $parent.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
}

# Find Operation ComboBox
Write-Host "Finding Operation ComboBox..."
$opCombo = Find-Control $window "CmbOperation"
if ($opCombo) {
    Write-Host "Operation ComboBox found"
    # Select "Compare & Verify" (index 3)
    $expandPattern = $opCombo.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
    $expandPattern.Expand()
    Start-Sleep -Milliseconds 500
    
    # Get list items
    $listCondition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::ListItem
    )
    $items = $opCombo.FindAll([System.Windows.Automation.TreeScope]::Descendants, $listCondition)
    
    if ($items.Count -gt 3) {
        $items[3].GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        Write-Host "Selected: Compare & Verify"
    }
    Start-Sleep -Milliseconds 500
} else {
    Write-Host "WARNING: Operation ComboBox not found by AutomationId"
}

# Find Task Name field
Write-Host "Finding Task Name field..."
$taskField = Find-Control $window "fld_TaskName"
if ($taskField) {
    $valuePattern = $taskField.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
    $valuePattern.SetValue("SYBASE-19337")
    Write-Host "Task Name set to: SYBASE-19337"
} else {
    Write-Host "WARNING: Task Name field not found"
}

# Find Password field
Write-Host "Finding Password field..."
$pwdField = Find-Control $window "PwdBox"
if ($pwdField) {
    $valuePattern = $pwdField.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
    $valuePattern.SetValue("sqlsql")
    Write-Host "Password set"
} else {
    Write-Host "WARNING: Password field not found"
}

# Find Run button
Write-Host "Finding Run button..."
$runBtn = Find-Control $window "BtnRun"
if ($runBtn) {
    Write-Host "Run button found, clicking..."
    $invokePattern = $runBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $invokePattern.Invoke()
    Write-Host "Run clicked!"
} else {
    Write-Host "WARNING: Run button not found"
}

# Wait for operation to complete
Write-Host "`nWaiting for operation to complete (max 60 seconds)..."
$startTime = [System.Diagnostics.Stopwatch]::StartNew()
$completed = $false

while ($startTime.Elapsed.TotalSeconds -lt 60 -and -not $completed) {
    Start-Sleep -Seconds 2
    
    # Check if Run button is enabled again (means operation completed)
    $runBtn = Find-Control $window "BtnRun"
    if ($runBtn) {
        $isEnabled = $runBtn.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::IsEnabledProperty)
        if ($isEnabled) {
            $completed = $true
            Write-Host "Operation completed!"
        }
    }
    
    Write-Host "  Elapsed: $([math]::Round($startTime.Elapsed.TotalSeconds))s"
}

if (-not $completed) {
    Write-Host "Timeout waiting for operation"
}

# Keep GUI open for inspection
Write-Host "`nGUI is still running. Close it manually or press Enter to kill it."
Read-Host

$guiProcess.Kill()
Write-Host "GUI closed"
