# Background operation runner for МОРДА2
# Выполнение операций в фоновом ThreadJob с обновлением UI через Dispatcher

function Start-BackgroundOperation {
    param(
        [scriptblock]$ScriptBlock,
        [hashtable]$Params = @{},
        [string]$OpName,
        [Windows.Controls.ProgressBar]$PhaseBar,
        [Windows.Controls.ProgressBar]$StepBar,
        [Windows.Controls.TextBlock]$PhaseLabel,
        [Windows.Controls.TextBlock]$StepLabel,
        [scriptblock]$OnComplete
    )

    Write-TechJournal "INFO" "Background: Starting $OpName"

    # ThreadJob работает в том же процессе, но в отдельном потоке
    # Это позволяет использовать Dispatcher.Invoke для обновления UI
    $job = Start-ThreadJob -ScriptBlock $ScriptBlock -ArgumentList $Params

    Write-TechJournal "INFO" "Background: ThreadJob $($job.Id) created for $OpName"

    # Таймер для мониторинга Job и обновления UI
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(200)
    $timer.Tag = @{
        Job = $job
        OnComplete = $OnComplete
        PhaseBar = $PhaseBar
        StepBar = $StepBar
        PhaseLabel = $PhaseLabel
        StepLabel = $StepLabel
        OpName = $OpName
        LastPhasePercent = 0
        LastStepPercent = 0
        PhaseName = ""
        StepName = ""
        OutputBuilder = New-Object System.Text.StringBuilder
    }

    $timer.Add_Tick({
        $t = $this
        $data = $t.Tag
        $job = $data.Job

        if ($job.State -eq 'Completed') {
            $t.Stop()
            Write-TechJournal "INFO" "Background: $($data.OpName) completed"

            try {
                # Получаем весь вывод
                $output = Receive-Job $job -ErrorAction Stop | Out-String
                Remove-Job $job -Force

                # Обновляем UI до 100%
                $data.PhaseBar.Dispatcher.Invoke({
                    $data.PhaseBar.Value = 100
                    $data.PhaseLabel.Text = "Завершено: $($data.OpName)"
                    $data.StepBar.Value = 100
                    $data.StepLabel.Text = "Готово"
                })

                # Вызываем callback
                if ($data.OnComplete) {
                    & $data.OnComplete $output
                }
            }
            catch {
                Write-TechJournal "ERROR" "Background: $($data.OpName) failed: $_"
                $data.PhaseBar.Dispatcher.Invoke({
                    $data.PhaseBar.Value = 0
                    $data.PhaseLabel.Text = "Ошибка: $_"
                    $data.StepBar.Value = 0
                    $data.StepLabel.Text = "Ошибка"
                })
                Remove-Job $job -Force -ErrorAction SilentlyContinue
            }
        }
        elseif ($job.State -eq 'Failed' -or $job.State -eq 'Stopped') {
            $t.Stop()
            Write-TechJournal "ERROR" "Background: $($data.OpName) failed with state $($job.State)"
            $data.PhaseBar.Dispatcher.Invoke({
                $data.PhaseBar.Value = 0
                $data.PhaseLabel.Text = "Ошибка: $($job.State)"
                $data.StepBar.Value = 0
                $data.StepLabel.Text = "Ошибка"
            })
            Remove-Job $job -Force -ErrorAction SilentlyContinue
        }
        elseif ($job.State -eq 'Running') {
            # Читаем новые строки из Job
            $newOutput = Receive-Job $job -ErrorAction SilentlyContinue | Out-String

            if ($newOutput) {
                $lines = $newOutput -split "`r?`n"

                foreach ($line in $lines) {
                    if ([string]::IsNullOrWhiteSpace($line)) { continue }

                    # Парсим ###PHASE###Название|значение###
                    if ($line -match '###PHASE###(.+?)\|(\d+)###') {
                        $data.PhaseName = $matches[1]
                        $percent = [int]$matches[2]
                        $data.LastPhasePercent = $percent

                        # Обновляем UI через Dispatcher
                        $data.PhaseBar.Dispatcher.Invoke({
                            $data.PhaseBar.Value = $percent
                            $data.PhaseLabel.Text = "$($data.PhaseName) [$percent%]"
                        })
                        Write-TechJournal "DEBUG" "PHASE: $($data.PhaseName) = $percent%"
                    }
                    # Парсим ###STEP###текст|значение###
                    elseif ($line -match '###STEP###(.+?)\|(\d+)###') {
                        $data.StepName = $matches[1]
                        $percent = [int]$matches[2]
                        $data.LastStepPercent = $percent

                        # Обновляем UI через Dispatcher
                        $data.StepBar.Dispatcher.Invoke({
                            $data.StepBar.Value = $percent
                            $data.StepLabel.Text = "$($data.StepName) [$percent%]"
                        })
                        Write-TechJournal "DEBUG" "STEP: $($data.StepName) = $percent%"
                    }
                }
            }

            # Если прогресс ещё не начался, показываем что выполняется
            if ($data.LastPhasePercent -eq 0) {
                $data.PhaseLabel.Dispatcher.Invoke({
                    $data.PhaseLabel.Text = "Выполнение: $($data.OpName)..."
                    $data.StepLabel.Text = "Обработка..."
                })
            }
        }
    })

    $timer.Start()
    Write-TechJournal "INFO" "Background: Timer started for $OpName"
}
