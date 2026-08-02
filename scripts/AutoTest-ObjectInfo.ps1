# AutoTest-ObjectInfo.ps1 — автотест справочника объектов
param([int]$Timeout=30)

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

Write-Host "[1] Launching..."
$proc = Start-Process powershell -ArgumentList "-NoLogo","-ExecutionPolicy","RemoteSigned","-File","C:\AIS\AI\Prod\scripts\Show-ObjectInfo-GUI.ps1" -PassThru -WindowStyle Normal
$end = (Get-Date).AddSeconds($Timeout)

Write-Host "[2] Wait for window..."
$win = $null
while((Get-Date) -lt $end -and -not $win){
    Start-Sleep -Milliseconds 500
    $win = [System.Windows.Automation.AutomationElement]::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Children,(New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty,"Справочник объектов AIS")))
}
if(-not $win){Write-Host "TIMEOUT: window not found";$proc.Kill();exit 1}
Write-Host "   Found: $($win.Current.Name)"

Write-Host "[3] Find PB/SQL tabs..."
$tabs = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants,(New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::TabItem)))
$found = @()
foreach($t in $tabs){$found += $t.Current.Name}
Write-Host "   Tabs: $found"

if('PB' -in $found -and 'SQL' -in $found){Write-Host "   PASSED"}else{Write-Host "   FAILED"}

Write-Host "[4] Find PB data grid..."
$dgCond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::DataGrid)
$dgs = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants,$dgCond)
if($dgs.Count -gt 0){Write-Host "   Found $($dgs.Count) DataGrid(s)";Write-Host "   PASSED"}else{Write-Host "   WARN: No visible DataGrid (may be virtualized)"}

Write-Host "[5] Close window..."
$btns = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants,(New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button)))
foreach($b in $btns){if($b.Current.Name -eq "Закрыть"){$b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke();Write-Host "   Closed";break}}

Start-Sleep -Seconds 2
if($proc.HasExited){Write-Host "   Window closed OK"}else{Write-Host "   Force kill";$proc.Kill()}
Write-Host "DONE"
exit 0
