# ============================================================
# AUTO TIME ZONE FROM PUBLIC IP - WINDOWS 11
# Checks public IP every 5 seconds
# Runs completely hidden as SYSTEM
# ============================================================

$ErrorActionPreference = "Stop"

# ------------------------------------------------------------
# 1. ENABLE TLS 1.2
# ------------------------------------------------------------

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host "Installing required PowerShell module..."

# ------------------------------------------------------------
# 2. INSTALL NUGET + WINTZ FOR ALL USERS
# ------------------------------------------------------------

try {
    Install-PackageProvider -Name NuGet -Force -ErrorAction SilentlyContinue | Out-Null
} catch {}

try {
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
} catch {}

Install-Module WinTZ -Scope AllUsers -Force -AllowClobber

Import-Module WinTZ -Force

Write-Host "WinTZ installed successfully."

# ------------------------------------------------------------
# 3. CREATE FOLDER
# ------------------------------------------------------------

$Folder = "C:\ProgramData\IPTimeZone"

New-Item `
    -ItemType Directory `
    -Path $Folder `
    -Force | Out-Null


# ------------------------------------------------------------
# 4. CREATE BACKGROUND SCRIPT
# ------------------------------------------------------------

$ScriptPath = "$Folder\AutoTimeZone.ps1"

@'
$StateFile = "C:\ProgramData\IPTimeZone\LastIP.txt"
$LogFile   = "C:\ProgramData\IPTimeZone\Log.txt"

# Load module from machine-wide module location
Import-Module WinTZ -Force -ErrorAction Stop

while ($true) {

    try {

        # ----------------------------------------------------
        # GET CURRENT PUBLIC IP
        # ----------------------------------------------------

        $CurrentIP = (
            & "$env:SystemRoot\System32\curl.exe" `
            -s `
            --max-time 4 `
            "https://api.ipify.org"
        ).Trim()


        # Make sure response looks like an IPv4 or IPv6 address

        if (
            $CurrentIP -and
            $CurrentIP -match '^[0-9a-fA-F:.]+$'
        ) {

            # ------------------------------------------------
            # READ PREVIOUS IP
            # ------------------------------------------------

            $LastIP = ""

            if (Test-Path $StateFile) {

                $LastIP = (
                    Get-Content `
                    $StateFile `
                    -Raw `
                    -ErrorAction SilentlyContinue
                ).Trim()

            }


            # ------------------------------------------------
            # ONLY CHECK TIMEZONE WHEN PUBLIC IP CHANGES
            # ------------------------------------------------

            if ($CurrentIP -ne $LastIP) {

                Add-Content `
                    -Path $LogFile `
                    -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | IP CHANGE DETECTED: $LastIP -> $CurrentIP"


                # --------------------------------------------
                # DETECT IANA TIMEZONE FROM PUBLIC IP
                # --------------------------------------------

                $IanaZone = Get-IANATimeZone


                Add-Content `
                    -Path $LogFile `
                    -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Detected IANA timezone: $IanaZone"


                # --------------------------------------------
                # CHANGE WINDOWS TIMEZONE
                # --------------------------------------------

                Set-WindowsTimeZone -Force


                # Give Windows a moment to apply change

                Start-Sleep -Seconds 1


                $WindowsZone = (Get-TimeZone).Id


                # --------------------------------------------
                # SAVE NEW IP ONLY AFTER SUCCESS
                # --------------------------------------------

                Set-Content `
                    -Path $StateFile `
                    -Value $CurrentIP `
                    -Force


                Add-Content `
                    -Path $LogFile `
                    -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Windows timezone changed to: $WindowsZone"

            }

        }

    }

    catch {

        Add-Content `
            -Path $LogFile `
            -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | ERROR: $($_.Exception.Message)"

    }


    # --------------------------------------------------------
    # WAIT 5 SECONDS
    # --------------------------------------------------------

    Start-Sleep -Seconds 5
}
'@ | Set-Content `
    -Path $ScriptPath `
    -Encoding UTF8 `
    -Force


Write-Host "Background script created."


# ------------------------------------------------------------
# 5. REMOVE OLD TASKS
# ------------------------------------------------------------

$OldTasks = @(
    "Auto Time Zone From Public IP",
    "IP Based Auto Time Zone",
    "IP Auto Time Zone Background"
)

foreach ($Task in $OldTasks) {

    Stop-ScheduledTask `
        -TaskName $Task `
        -ErrorAction SilentlyContinue

    Unregister-ScheduledTask `
        -TaskName $Task `
        -Confirm:$false `
        -ErrorAction SilentlyContinue
}


# ------------------------------------------------------------
# 6. KILL ANY OLD AUTOTIMEZONE POWERSHELL PROCESS
# ------------------------------------------------------------

Get-CimInstance Win32_Process `
    -Filter "Name='powershell.exe'" `
    -ErrorAction SilentlyContinue |
Where-Object {
    $_.CommandLine -like "*AutoTimeZone.ps1*"
} |
ForEach-Object {

    Stop-Process `
        -Id $_.ProcessId `
        -Force `
        -ErrorAction SilentlyContinue
}


# ------------------------------------------------------------
# 7. DELETE OLD IP SO FIRST RUN IS FORCED
# ------------------------------------------------------------

Remove-Item `
    "$Folder\LastIP.txt" `
    -Force `
    -ErrorAction SilentlyContinue

Remove-Item `
    "$Folder\Log.txt" `
    -Force `
    -ErrorAction SilentlyContinue


# ------------------------------------------------------------
# 8. CREATE HIDDEN SYSTEM SCHEDULED TASK
# ------------------------------------------------------------

$Action = New-ScheduledTaskAction `
    -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -Argument '-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\ProgramData\IPTimeZone\AutoTimeZone.ps1"'


$Trigger = New-ScheduledTaskTrigger `
    -AtStartup


$Settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero)


Register-ScheduledTask `
    -TaskName "IP Auto Time Zone Background" `
    -Action $Action `
    -Trigger $Trigger `
    -Settings $Settings `
    -User "SYSTEM" `
    -RunLevel Highest `
    -Force | Out-Null


# ------------------------------------------------------------
# 9. START IT NOW
# ------------------------------------------------------------

Start-ScheduledTask `
    -TaskName "IP Auto Time Zone Background"


Write-Host ""
Write-Host "Background timezone service started."
Write-Host "Waiting for first IP detection..."
Write-Host ""


# ------------------------------------------------------------
# 10. WAIT FOR FIRST CHECK
# ------------------------------------------------------------

Start-Sleep -Seconds 8


# ------------------------------------------------------------
# 11. SHOW STATUS
# ------------------------------------------------------------

Write-Host "==============================="
Write-Host "TASK STATUS"
Write-Host "==============================="

Get-ScheduledTask `
    -TaskName "IP Auto Time Zone Background" |
Select-Object TaskName, State


Write-Host ""
Write-Host "==============================="
Write-Host "CURRENT PUBLIC IP"
Write-Host "==============================="

& "$env:SystemRoot\System32\curl.exe" `
    -s `
    "https://api.ipify.org"


Write-Host ""
Write-Host ""
Write-Host "==============================="
Write-Host "CURRENT WINDOWS TIMEZONE"
Write-Host "==============================="

Get-TimeZone


Write-Host ""
Write-Host "==============================="
Write-Host "LOG"
Write-Host "==============================="

if (Test-Path "$Folder\Log.txt") {

    Get-Content `
        "$Folder\Log.txt" `
        -Tail 20

}
else {

    Write-Host "No log created yet."
}


Write-Host ""
Write-Host "Setup complete."
