# Registers the Turnstile house agents as Windows scheduled tasks on this PC.
# Rounds open at 08:00 UTC (worker/src/time.ts). The schedule, all UTC:
#   06:30 construct (claude)   06:34 construct (gpt)      -> tomorrow's two machines uploaded
#   07:15 investigate (gpt)    07:25 investigate (claude) -> each cracks the rival's machine blind
#   08:10 play (sonnet)        08:14 play (haiku)         -> ordinary house players on today's round
# Tasks retry every 30 minutes for six hours if the box was asleep.
# Run once from an elevated PowerShell:  powershell -ExecutionPolicy Bypass -File install_house_agents.ps1
# Remove with:  Get-ScheduledTask -TaskPath \ | Where-Object TaskName -like "Turnstile *" | Unregister-ScheduledTask -Confirm:$false
# Tokens live in ~/.turnstile/<brain>.token (see README "House agents").

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$python = (Get-Command python).Source

$jobs = @(
    @{ name = "Turnstile construct (claude)";   script = "house_construct.py";   args = "claude";          minutesUtc = 6 * 60 + 30 },
    @{ name = "Turnstile construct (gpt)";      script = "house_construct.py";   args = "gpt";             minutesUtc = 6 * 60 + 34 },
    @{ name = "Turnstile investigate (gpt)";    script = "house_investigate.py"; args = "gpt --pending";   minutesUtc = 7 * 60 + 15 },
    @{ name = "Turnstile investigate (claude)"; script = "house_investigate.py"; args = "claude --pending"; minutesUtc = 7 * 60 + 25 },
    @{ name = "Turnstile play (sonnet)";        script = "house_investigate.py"; args = "sonnet --today";  minutesUtc = 8 * 60 + 10 },
    @{ name = "Turnstile play (haiku)";         script = "house_investigate.py"; args = "haiku --today";   minutesUtc = 8 * 60 + 14 }
)
foreach ($job in $jobs) {
    $startUtc = [DateTime]::UtcNow.Date.AddMinutes($job.minutesUtc)
    $startLocal = $startUtc.ToLocalTime()
    $action = New-ScheduledTaskAction -Execute $python -Argument "`"$here\$($job.script)`" $($job.args)" -WorkingDirectory $here
    $trigger = New-ScheduledTaskTrigger -Daily -At $startLocal
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RestartCount 12 -RestartInterval (New-TimeSpan -Minutes 30) `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -WakeToRun
    Register-ScheduledTask -TaskName $job.name -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
    Write-Host "registered '$($job.name)' daily at $($startLocal.ToString('HH:mm')) local ($($startUtc.ToString('HH:mm'))Z)"
}
