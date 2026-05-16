# WINDOWS OPENSSH TEK PANEL v13 PORT_READ_FIX
# Servis + Aktif SSH oturumlari + Firewall + Port/Config yonetimi
# Yonetici PowerShell ile calistir.

$ConfigPath = "C:\ProgramData\ssh\sshd_config"
$SshdExe = "$env:WINDIR\System32\OpenSSH\sshd.exe"
$FirewallRuleName = "OpenSSH-Server-In-TCP"

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    Write-Host "Bu panel Yonetici PowerShell ile calismalidir."
    Write-Host "PowerShell'e sag tikla > Yonetici olarak calistir."
    Read-Host "Cikmak icin Enter'a bas"
    exit
}

function Wait-Enter {
    Write-Host ""
    Read-Host "Devam etmek icin Enter'a bas"
}

function Get-CurrentSshPort {
    # Mantik:
    # Port ayari global ayardir. Match blogunun icindeki Port satirlari gecersizdir.
    # Bu yuzden sadece ilk Match satirindan ONCEKI aktif Port satirlarini okuruz.
    # Aktif Port yoksa OpenSSH varsayilani 22 kabul edilir.

    if (-not (Test-Path $ConfigPath)) {
        return 22
    }

    $content = Get-Content $ConfigPath -ErrorAction SilentlyContinue

    if (-not $content) {
        return 22
    }

    $activePort = $null
    $insideMatchBlock = $false

    foreach ($line in $content) {
        $trimmed = $line.Trim()

        if ($trimmed -match '^#') {
            continue
        }

        if ($trimmed -match '^Match\s+') {
            $insideMatchBlock = $true
            continue
        }

        if (-not $insideMatchBlock -and $trimmed -match '^Port\s+(\d+)(\s+.*)?$') {
            $activePort = [int]$Matches[1]
        }
    }

    if ($activePort) {
        return $activePort
    }

    return 22
}

function Get-SshService {
    return Get-CimInstance Win32_Service -Filter "Name='sshd'" -ErrorAction SilentlyContinue
}

function Get-SshFirewallRules {
    $rules = @()

    $rules += Get-NetFirewallRule -Name "*SSH*" -ErrorAction SilentlyContinue
    $rules += Get-NetFirewallRule -Name "*OpenSSH*" -ErrorAction SilentlyContinue
    $rules += Get-NetFirewallRule -DisplayName "*SSH*" -ErrorAction SilentlyContinue
    $rules += Get-NetFirewallRule -DisplayName "*OpenSSH*" -ErrorAction SilentlyContinue

    $rules = $rules |
        Where-Object { $_ -ne $null } |
        Sort-Object Name -Unique

    foreach ($rule in $rules) {
        $port = $rule | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
        $addr = $rule | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue

        [PSCustomObject]@{
            Name          = $rule.Name
            DisplayName   = $rule.DisplayName
            Enabled       = $rule.Enabled
            Direction     = $rule.Direction
            Action        = $rule.Action
            Protocol      = if ($port) { ($port.Protocol -join ",") } else { "-" }
            LocalPort     = if ($port) { ($port.LocalPort -join ",") } else { "-" }
            RemoteAddress = if ($addr) { ($addr.RemoteAddress -join ",") } else { "-" }
            Profile       = $rule.Profile
        }
    }
}

function Show-SshFirewallRules {
    $rules = Get-SshFirewallRules

    if ($rules) {
        $rules |
            Sort-Object Action, Enabled, Name |
            Format-Table -AutoSize
    }
    else {
        Write-Host "SSH veya OpenSSH isimli firewall kurali bulunamadi."
    }
}

function Ensure-OpenSshFirewallRule {
    param(
        [int]$Port
    )

    $rule = Get-NetFirewallRule -Name $FirewallRuleName -ErrorAction SilentlyContinue

    if (-not $rule) {
        $params = @{
            Name        = $FirewallRuleName
            DisplayName = "OpenSSH Server TCP $Port"
            Enabled     = "True"
            Direction   = "Inbound"
            Action      = "Allow"
            Protocol    = "TCP"
            LocalPort   = $Port
        }

        New-NetFirewallRule @params | Out-Null
        $rule = Get-NetFirewallRule -Name $FirewallRuleName -ErrorAction SilentlyContinue
    }

    return $rule
}

function Show-Dashboard {
    Clear-Host

    $currentPort = Get-CurrentSshPort

    Write-Host "======================================"
    Write-Host " WINDOWS OPENSSH TEK PANEL v13 PORT_READ_FIX"
    Write-Host "======================================"
    Write-Host ""

    Write-Host "1) SSH SERVIS DURUMU:"
    $service = Get-Service sshd -ErrorAction SilentlyContinue

    if ($service) {
        $service | Select-Object Status, Name, DisplayName | Format-Table -AutoSize
    }
    else {
        Write-Host "sshd servisi bulunamadi."
    }

    Write-Host ""
    Write-Host "2) SSH CONFIG:"
    if (Test-Path $ConfigPath) {
        Write-Host "Config dosyasi: $ConfigPath"
    }
    else {
        Write-Host "Config dosyasi bulunamadi: $ConfigPath"
    }

    Write-Host "Aktif SSH portu: $currentPort"

    Write-Host ""
    Write-Host "3) PORT $currentPort LISTEN DURUMU:"
    $listen = Get-NetTCPConnection -LocalPort $currentPort -State Listen -ErrorAction SilentlyContinue

    if ($listen) {
        $listen |
            Select-Object LocalAddress, LocalPort, State, OwningProcess |
            Format-Table -AutoSize
    }
    else {
        Write-Host "Port $currentPort LISTEN durumda degil."
    }

    Write-Host ""
    Write-Host "4) AKTIF SSH OTURUM PROCESS DURUMU:"
    Write-Host "Ana ekranda gosterilmiyor. Aktif SSH oturumlarini gormek ve kill etmek icin ana menuden 5'i sec."

    Write-Host ""
    Write-Host "5) FIREWALL KURALLARI:"
    Write-Host "Ana ekranda gosterilmiyor. Firewall kurallarini gormek icin ana menuden 6'yi sec."
}

function Backup-SshConfig {
    if (-not (Test-Path $ConfigPath)) {
        Write-Host "sshd_config bulunamadi, yedek alinamadi."
        return $null
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = "$ConfigPath.bak-$timestamp"

    Copy-Item -Path $ConfigPath -Destination $backupPath -Force

    Write-Host "Yedek alindi: $backupPath"

    return $backupPath
}

function Test-SshConfig {
    if (-not (Test-Path $SshdExe)) {
        Write-Host "sshd.exe bulunamadi: $SshdExe"
        return $false
    }

    if (-not (Test-Path $ConfigPath)) {
        Write-Host "sshd_config bulunamadi: $ConfigPath"
        return $false
    }

    Write-Host "sshd_config test ediliyor..."

    & $SshdExe -t -f $ConfigPath

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Config testi basarili."
        return $true
    }
    else {
        Write-Host "Config testinde hata var."
        return $false
    }
}

function Set-SshFirewallPort {
    param(
        [int]$Port
    )

    $rule = Ensure-OpenSshFirewallRule -Port $Port

    Set-NetFirewallRule -Name $FirewallRuleName -Enabled True -Direction Inbound -Action Allow

    $portFilter = $rule | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue

    if ($portFilter) {
        $portFilter | Set-NetFirewallPortFilter -Protocol TCP -LocalPort $Port
    }

    Write-Host "Firewall OpenSSH kural portu $Port olarak ayarlandi."
}

function Set-PortLineBeforeMatchBlock {
    param(
        [int]$NewPort
    )

    # Mantik:
    # 1) Aktif Port satirlarinin tamamini yorum satirina cevirir.
    #    Buna Match blogu icinde kalmis hatali Port satirlari da dahildir.
    # 2) Yeni Port satirini ilk Match blogundan ONCE yazar.
    # 3) Match blogu yoksa dosyanin sonuna yazar.

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $content = Get-Content $ConfigPath -ErrorAction Stop
    $newContent = New-Object System.Collections.Generic.List[string]
    $inserted = $false

    for ($i = 0; $i -lt $content.Count; $i++) {
        $line = $content[$i]
        $trimmed = $line.Trim()

        if (-not $inserted -and $trimmed -match '^Match\s+') {
            $newContent.Add("")
            $newContent.Add("# Added by SSH panel $timestamp")
            $newContent.Add("Port $NewPort")
            $newContent.Add("")
            $inserted = $true
        }

        if ($trimmed -notmatch '^#' -and $trimmed -match '^Port\s+\d+(\s+.*)?$') {
            $newContent.Add("# DISABLED_BY_SCRIPT $timestamp : $line")
        }
        else {
            $newContent.Add($line)
        }
    }

    if (-not $inserted) {
        $newContent.Add("")
        $newContent.Add("# Added by SSH panel $timestamp")
        $newContent.Add("Port $NewPort")
    }

    Set-Content -Path $ConfigPath -Value $newContent -Encoding ascii
}

function Show-SshPortConfigLines {
    Clear-Host
    Write-Host "=============================="
    Write-Host " SSH PORT SATIRI ANALIZI"
    Write-Host "=============================="
    Write-Host ""

    if (-not (Test-Path $ConfigPath)) {
        Write-Host "sshd_config bulunamadi: $ConfigPath"
        Wait-Enter
        return
    }

    $content = Get-Content $ConfigPath -ErrorAction SilentlyContinue
    $insideMatchBlock = $false
    $lineNo = 0
    $rows = foreach ($line in $content) {
        $lineNo++
        $trimmed = $line.Trim()

        if ($trimmed -notmatch '^#' -and $trimmed -match '^Match\s+') {
            $insideMatchBlock = $true
        }

        if ($trimmed -match '^(#\s*)?Port\s+\d+' -or $trimmed -match '^Match\s+') {
            [PSCustomObject]@{
                LineNo     = $lineNo
                InMatch    = if ($insideMatchBlock) { "Evet" } else { "Hayir" }
                Active     = if ($trimmed -notmatch '^#') { "Evet" } else { "Hayir" }
                Line       = $line
            }
        }
    }

    if ($rows) {
        $rows | Format-Table -AutoSize
    }
    else {
        Write-Host "Port veya Match satiri bulunamadi. Varsayilan SSH portu 22 kabul edilir."
    }

    Write-Host ""
    Write-Host "Panelin okudugu aktif SSH portu: $(Get-CurrentSshPort)"
    Write-Host "Not: Panel sadece Match blogundan ONCEKI aktif Port satirini gecerli sayar."
    Wait-Enter
}


function Get-SshdStatusText {
    $service = Get-Service sshd -ErrorAction SilentlyContinue

    if (-not $service) {
        return "Bulunamadi"
    }

    return [string]$service.Status
}

function Stop-SshdSafe {
    Write-Host "sshd servisi durduruluyor..."

    try {
        Stop-Service sshd -Force -ErrorAction Stop
    }
    catch {
        Write-Host "Stop-Service basarisiz oldu: $($_.Exception.Message)"
        Write-Host "sc.exe stop sshd denenecek..."
        sc.exe stop sshd | Out-Host
    }

    Start-Sleep -Seconds 2
    $status = Get-SshdStatusText

    if ($status -eq "Stopped") {
        Write-Host "sshd servisi durduruldu. Durum: $status"
        return $true
    }

    Write-Host "sshd servisi durdurulamadi. Mevcut durum: $status"
    Write-Host "Not: Eger SSH oturumu icinden calisiyorsan veya yetki/UAC sorunu varsa servis durmayabilir."
    return $false
}

function Start-SshdSafe {
    Write-Host "sshd servisi baslatiliyor..."

    try {
        Start-Service sshd -ErrorAction Stop
    }
    catch {
        Write-Host "Start-Service basarisiz oldu: $($_.Exception.Message)"
        Write-Host "sc.exe start sshd denenecek..."
        sc.exe start sshd | Out-Host
    }

    Start-Sleep -Seconds 2
    $status = Get-SshdStatusText

    if ($status -eq "Running") {
        Write-Host "sshd servisi baslatildi. Durum: $status"
        return $true
    }

    Write-Host "sshd servisi baslatilamadi. Mevcut durum: $status"
    return $false
}

function Restart-SshdSafe {
    Write-Host "sshd servisi yeniden baslatiliyor..."

    try {
        Restart-Service sshd -Force -ErrorAction Stop
    }
    catch {
        Write-Host "Restart-Service basarisiz oldu: $($_.Exception.Message)"
        Write-Host "Once stop, sonra start denenecek..."
        Stop-SshdSafe | Out-Null
        Start-SshdSafe | Out-Null
    }

    Start-Sleep -Seconds 2
    $status = Get-SshdStatusText

    if ($status -eq "Running") {
        Write-Host "sshd servisi calisiyor. Durum: $status"
        return $true
    }

    Write-Host "sshd servisi yeniden baslatma sonrasi calismiyor. Durum: $status"
    return $false
}

function Service-Menu {
    while ($true) {
        Clear-Host
        Write-Host "=============================="
        Write-Host " SSH SERVIS YONETIMI"
        Write-Host "=============================="
        Write-Host ""

        $service = Get-Service sshd -ErrorAction SilentlyContinue

        if ($service) {
            $service | Select-Object Status, Name, DisplayName | Format-Table -AutoSize
        }
        else {
            Write-Host "sshd servisi bulunamadi."
        }

        Write-Host ""
        Write-Host "1) sshd servisini baslat"
        Write-Host "2) sshd servisini durdur"
        Write-Host "3) sshd servisini yeniden baslat"
        Write-Host "4) Baslangici Automatic yap ve servisi baslat"
        Write-Host "5) Baslangici Manual yap"
        Write-Host "6) Servisi durdur ve Disabled yap"
        Write-Host "7) Servis durumunu yenile"
        Write-Host "B) Geri don"
        Write-Host ""

        $choice = Read-Host "Secim yap"

        switch ($choice) {
            "1" {
                Start-SshdSafe | Out-Null
                Wait-Enter
            }
            "2" {
                Write-Host "Dikkat: SSH ile bagliysan oturumun dusebilir."
                $confirm = Read-Host "Devam edilsin mi? E/H"
                if ($confirm -eq "E" -or $confirm -eq "e") {
                    Stop-SshdSafe | Out-Null
                }
                else {
                    Write-Host "Islem iptal edildi."
                }
                Wait-Enter
            }
            "3" {
                Write-Host "Dikkat: SSH ile bagliysan oturumun dusebilir."
                $confirm = Read-Host "Devam edilsin mi? E/H"
                if ($confirm -eq "E" -or $confirm -eq "e") {
                    Restart-SshdSafe | Out-Null
                }
                else {
                    Write-Host "Islem iptal edildi."
                }
                Wait-Enter
            }
            "4" {
                try {
                    Set-Service -Name sshd -StartupType Automatic -ErrorAction Stop
                    Start-SshdSafe | Out-Null
                    Write-Host "sshd Automatic baslangica alindi."
                }
                catch {
                    Write-Host "Automatic yapma basarisiz oldu: $($_.Exception.Message)"
                }
                Wait-Enter
            }
            "5" {
                try {
                    Set-Service -Name sshd -StartupType Manual -ErrorAction Stop
                    Write-Host "sshd Manual baslangica alindi."
                }
                catch {
                    Write-Host "Manual yapma basarisiz oldu: $($_.Exception.Message)"
                }
                Wait-Enter
            }
            "6" {
                Write-Host "Dikkat: SSH kapatilacak ve devre disi birakilacak."
                $confirm = Read-Host "Devam edilsin mi? E/H"
                if ($confirm -eq "E" -or $confirm -eq "e") {
                    Stop-SshdSafe | Out-Null
                    try {
                        Set-Service -Name sshd -StartupType Disabled -ErrorAction Stop
                        Write-Host "sshd Disabled yapildi."
                    }
                    catch {
                        Write-Host "Disabled yapma basarisiz oldu: $($_.Exception.Message)"
                    }
                }
                else {
                    Write-Host "Islem iptal edildi."
                }
                Wait-Enter
            }
            "7" { continue }
            "B" { return }
            "b" { return }
            default {
                Write-Host "Gecersiz secim."
                Wait-Enter
            }
        }
    }
}
function Get-SshdProcessTable {
    $sshdService = Get-SshService

    if (-not $sshdService) {
        Write-Host "sshd servisi bulunamadi."
        return @()
    }

    if ($sshdService.State -ne "Running") {
        Write-Host "sshd servisi calismiyor. Once baslat:"
        Write-Host "Start-Service sshd"
        return @()
    }

    $serviceProcId = [int]$sshdService.ProcessId
    $processes = @(Get-CimInstance Win32_Process -Filter "Name='sshd.exe'" -ErrorAction SilentlyContinue)

    if (-not $processes -or $processes.Count -eq 0) {
        return @()
    }

    $processMap = @{}
    foreach ($proc in $processes) {
        $processMap[[int]$proc.ProcessId] = $proc
    }

    $result = foreach ($proc in $processes) {
        $procId = [int]$proc.ProcessId
        $parentProcId = [int]$proc.ParentProcessId
        $cmd = $proc.CommandLine

        $role = ""
        $sessionRootProcId = $null
        $killAllowed = "Hayir"

        if ($procId -eq $serviceProcId) {
            $role = "ANA SERVIS / LISTENER - OLDURME"
        }
        elseif ($parentProcId -eq $serviceProcId) {
            $sessionRootProcId = $procId
            $killAllowed = "Evet"

            if ($cmd -like "* -R*") {
                $role = "SSH OTURUM KOK SURECI (-R)"
            }
            elseif ($cmd -like "* -z*") {
                $role = "SSH OTURUM KOK SURECI (-z)"
            }
            elseif ($cmd -like "* -y*") {
                $role = "SSH OTURUM KOK SURECI (-y)"
            }
            else {
                $role = "SSH OTURUM KOK SURECI"
            }
        }
        else {
            $walkProc = $proc
            $rootProcId = $null

            while ($true) {
                $walkParentProcId = [int]$walkProc.ParentProcessId

                if ($walkParentProcId -eq $serviceProcId) {
                    $rootProcId = [int]$walkProc.ProcessId
                    break
                }

                if ($processMap.ContainsKey($walkParentProcId)) {
                    $walkProc = $processMap[$walkParentProcId]
                }
                else {
                    break
                }
            }

            if ($rootProcId) {
                $sessionRootProcId = $rootProcId
                $killAllowed = "Evet"

                if ($cmd -like "* -z*") {
                    $role = "SSH OTURUM ALT/YARDIMCI SURECI (-z)"
                }
                elseif ($cmd -like "* -y*") {
                    $role = "SSH OTURUM ALT/YARDIMCI SURECI (-y)"
                }
                elseif ($cmd -like "* -R*") {
                    $role = "SSH OTURUM ALT/YARDIMCI SURECI (-R)"
                }
                else {
                    $role = "SSH OTURUM ALT/YARDIMCI SURECI"
                }
            }
            else {
                $role = "DIGER SSHD SURECI"
            }
        }

        [PSCustomObject]@{
            ProcessId       = $procId
            ParentProcessId = $parentProcId
            SessionRootPid  = if ($sessionRootProcId) { $sessionRootProcId } else { "-" }
            KillAllowed     = $killAllowed
            Role            = $role
            CommandLine     = $cmd
        }
    }

    return @($result)
}

function Get-SshSessionSummary {
    $table = @(Get-SshdProcessTable)

    $sessions = @($table |
        Where-Object { $_.KillAllowed -eq "Evet" -and $_.SessionRootPid -ne "-" } |
        Group-Object SessionRootPid |
        ForEach-Object {
            $rootProcId = [int]$_.Name
            $groupRows = @($_.Group)

            $allProcIds = @($groupRows |
                Select-Object -ExpandProperty ProcessId |
                ForEach-Object { [int]$_ } |
                Sort-Object -Unique)

            $childProcIds = @($allProcIds | Where-Object { $_ -ne $rootProcId })

            $parentProcIds = @($groupRows |
                Select-Object -ExpandProperty ParentProcessId |
                ForEach-Object { [int]$_ })

            $leafProcIds = @($groupRows |
                Where-Object {
                    $thisProcId = [int]$_.ProcessId
                    ($parentProcIds -notcontains $thisProcId) -and ($thisProcId -ne $rootProcId)
                } |
                Select-Object -ExpandProperty ProcessId |
                ForEach-Object { [int]$_ } |
                Sort-Object -Unique)

            if ($leafProcIds -and $leafProcIds.Count -gt 0) {
                $suggestedKillProcId = [int]($leafProcIds[-1])
            }
            else {
                $suggestedKillProcId = $rootProcId
            }

            [PSCustomObject]@{
                SessionRootPid  = $rootProcId
                SuggestedKillPid = $suggestedKillProcId
                ChildPids       = if ($childProcIds -and $childProcIds.Count -gt 0) { ($childProcIds -join ",") } else { "-" }
                AllPids         = ($allProcIds -join ",")
                Aciklama        = "Ayni SSH oturumu. Listedeki herhangi bir PID secilebilir."
            }
        })

    return @($sessions)
}

function Show-SshSessionProcessesOnly {
    $sshdService = Get-SshService

    if (-not $sshdService) {
        Write-Host "sshd servisi bulunamadi."
        return
    }

    if ($sshdService.State -ne "Running") {
        Write-Host "sshd servisi calismiyor."
        return
    }

    $serviceProcId = [int]$sshdService.ProcessId
    Write-Host "Ana sshd servis PID: $serviceProcId"
    Write-Host "Ana servis oldurulmez. Oturum kesmek icin 2 numarali menuden PID secilir."
    Write-Host ""

    $rows = @(Get-SshdProcessTable)

    if ($rows -and $rows.Count -gt 0) {
        Write-Host "DETAYLI PROCESS LISTESI:"
        $rows |
            Sort-Object @{Expression={ if ($_.SessionRootPid -eq "-") { 0 } else { [int]$_.SessionRootPid } }}, ProcessId |
            Format-Table ProcessId, ParentProcessId, SessionRootPid, KillAllowed, Role, CommandLine -AutoSize

        Write-Host ""
        Write-Host "OTURUM OZETI:"
        $summary = @(Get-SshSessionSummary)
        if ($summary -and $summary.Count -gt 0) {
            $summary | Format-Table -AutoSize
        }
        else {
            Write-Host "Aktif SSH oturumu bulunamadi."
        }
    }
    else {
        Write-Host "sshd.exe process bilgisi bulunamadi."
    }
}

function Show-SshSessionProcesses {
    Clear-Host
    Write-Host "=============================="
    Write-Host " AKTIF SSH OTURUM PROCESS LISTESI"
    Write-Host "=============================="
    Write-Host ""

    Show-SshSessionProcessesOnly

    Write-Host ""
    Write-Host "Kural:"
    Write-Host "ANA SERVIS / LISTENER oldurulmez."
    Write-Host "Ayni SSH oturumuna ait processler ayni SessionRootPid altinda gosterilir."
    Write-Host "PID secersen script once sectigin PID'yi dener; olmazsa ayni oturumdaki diger PID'leri sirayla dener."
    Wait-Enter
}

function Invoke-TaskKillSafe {
    param(
        [int]$TargetProcId
    )

    $exists = Get-CimInstance Win32_Process -Filter "ProcessId=$TargetProcId" -ErrorAction SilentlyContinue

    if (-not $exists) {
        Write-Host "$TargetProcId PID su anda process listesinde yok, atlandi."
        return $false
    }

    taskkill.exe /PID $TargetProcId /T /F | Out-Host

    if ($LASTEXITCODE -eq 0) {
        return $true
    }

    return $false
}

function Get-KillCandidatesForSession {
    param(
        [int]$SelectedProcId,
        [object]$Session
    )

    $candidateList = New-Object System.Collections.Generic.List[int]

    $allProcIds = @($Session.AllPids -split "," |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -match '^\d+$' } |
        ForEach-Object { [int]$_ })

    if ($allProcIds -contains $SelectedProcId) {
        $candidateList.Add($SelectedProcId)
    }

    if ($Session.SuggestedKillPid -and [string]$Session.SuggestedKillPid -match '^\d+$') {
        $candidateList.Add([int]$Session.SuggestedKillPid)
    }

    if ($Session.SessionRootPid -and [string]$Session.SessionRootPid -match '^\d+$') {
        $candidateList.Add([int]$Session.SessionRootPid)
    }

    foreach ($oneProcId in ($allProcIds | Sort-Object -Descending)) {
        $candidateList.Add([int]$oneProcId)
    }

    return @($candidateList | Select-Object -Unique)
}

function Kill-SelectedSshSession {
    $sshdService = Get-SshService

    if (-not $sshdService) {
        Write-Host "sshd servisi bulunamadi."
        Wait-Enter
        return
    }

    if ($sshdService.State -ne "Running") {
        Write-Host "sshd servisi calismiyor. Once baslat:"
        Write-Host "Start-Service sshd"
        Wait-Enter
        return
    }

    $serviceProcId = [int]$sshdService.ProcessId
    $table = @(Get-SshdProcessTable)
    $summary = @(Get-SshSessionSummary)

    if (-not $summary -or $summary.Count -eq 0) {
        Write-Host "Aktif SSH oturumu bulunamadi."
        Wait-Enter
        return
    }

    Write-Host ""
    Write-Host "=============================="
    Write-Host " SECILEN SSH OTURUMUNU KILL ET"
    Write-Host "=============================="
    Write-Host "Ana sshd servis PID: $serviceProcId  (OLDURME)"
    Write-Host ""
    Write-Host "OTURUM OZETI:"
    $summary | Format-Table -AutoSize
    Write-Host ""
    Write-Host "PID olarak SessionRootPid, SuggestedKillPid veya AllPids icindeki herhangi bir PID girilebilir."
    Write-Host "Script once sectigin PID'yi dener, olmuyorsa ayni oturumdaki diger PID'leri sirayla dener."
    Write-Host ""

    $pidInput = Read-Host "Kesilecek SSH oturumu icin PID gir"

    if (-not ($pidInput -match '^\d+$')) {
        Write-Host "Gecersiz PID. Sadece sayi gir."
        Wait-Enter
        return
    }

    $selectedProcId = [int]$pidInput

    if ($selectedProcId -eq $serviceProcId) {
        Write-Host "$selectedProcId ANA SERVIS / LISTENER PID'sidir. ISLEM YAPILMADI."
        Write-Host "Bu PID oldurulurse SSH servisi komple durabilir."
        Wait-Enter
        return
    }

    $selectedRow = $table | Where-Object { [int]$_.ProcessId -eq $selectedProcId } | Select-Object -First 1

    if (-not $selectedRow) {
        Write-Host "$selectedProcId PID listede bulunamadi."
        Wait-Enter
        return
    }

    if ($selectedRow.KillAllowed -ne "Evet") {
        Write-Host "$selectedProcId kill icin uygun SSH oturum sureci degil."
        Wait-Enter
        return
    }

    $session = $summary | Where-Object {
        $oneSessionProcIds = @($_.AllPids -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
        $oneSessionProcIds -contains ([string]$selectedProcId)
    } | Select-Object -First 1

    if (-not $session) {
        Write-Host "$selectedProcId icin bagli SSH oturumu bulunamadi."
        Wait-Enter
        return
    }

    $killCandidates = @(Get-KillCandidatesForSession -SelectedProcId $selectedProcId -Session $session)

    Write-Host ""
    Write-Host "Secilen PID       : $selectedProcId"
    Write-Host "SessionRootPid    : $($session.SessionRootPid)"
    Write-Host "SuggestedKillPid  : $($session.SuggestedKillPid)"
    Write-Host "ChildPids         : $($session.ChildPids)"
    Write-Host "Denenecek PID'ler : $($killCandidates -join ',')"
    Write-Host ""

    $success = $false

    foreach ($candidateProcId in $killCandidates) {
        if ($candidateProcId -eq $serviceProcId) {
            continue
        }

        Write-Host "$candidateProcId PID deneniyor..."
        $success = Invoke-TaskKillSafe -TargetProcId $candidateProcId

        if ($success) {
            Write-Host "$candidateProcId PID ile SSH oturumu sonlandirildi."
            break
        }
    }

    if (-not $success) {
        Write-Host "Bu oturum icin denenen PID'lerle kill islemi basarisiz oldu."
        Write-Host "Not: SSH oturumu zaten dusmus veya process listesi degismis olabilir."
    }

    Wait-Enter
}

function Kill-AllSshSessions {
    Clear-Host
    Write-Host "=============================="
    Write-Host " TUM SSH OTURUMLARINI KILL ET"
    Write-Host "=============================="
    Write-Host ""

    $sshdService = Get-SshService

    if (-not $sshdService -or $sshdService.State -ne "Running") {
        Write-Host "sshd servisi calismiyor veya bulunamadi."
        Wait-Enter
        return
    }

    $serviceProcId = [int]$sshdService.ProcessId
    $summary = @(Get-SshSessionSummary)

    if (-not $summary -or $summary.Count -eq 0) {
        Write-Host "Kill edilecek aktif SSH oturumu bulunamadi."
        Wait-Enter
        return
    }

    Write-Host "Kill edilecek SSH oturumlari:"
    $summary | Format-Table -AutoSize

    Write-Host ""
    $confirm = Read-Host "Listelenen TUM SSH oturumlari kesilsin mi? E/H"

    if ($confirm -ne "E" -and $confirm -ne "e") {
        Write-Host "Islem iptal edildi."
        Wait-Enter
        return
    }

    foreach ($session in $summary) {
        $allIds = @($session.AllPids -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
        $firstId = if ($session.SuggestedKillPid -and [string]$session.SuggestedKillPid -match '^\d+$') { [int]$session.SuggestedKillPid } else { [int]$session.SessionRootPid }
        $dummySession = $session
        $candidates = @(Get-KillCandidatesForSession -SelectedProcId $firstId -Session $dummySession)

        Write-Host "SessionRootPid $($session.SessionRootPid) icin denenecek PID'ler: $($candidates -join ',')"

        foreach ($candidateProcId in $candidates) {
            if ($candidateProcId -eq $serviceProcId) {
                continue
            }

            $ok = Invoke-TaskKillSafe -TargetProcId $candidateProcId
            if ($ok) {
                Write-Host "SessionRootPid $($session.SessionRootPid) kesildi."
                break
            }
        }
    }

    Wait-Enter
}

function SshSession-Menu {
    while ($true) {
        Clear-Host
        Write-Host "=============================="
        Write-Host " AKTIF SSH OTURUM YONETIMI"
        Write-Host "=============================="
        Write-Host ""

        Show-SshSessionProcessesOnly

        Write-Host ""
        Write-Host "1) Aktif SSH oturum process listesini yenile"
        Write-Host "2) Secilen SSH oturumunu PID ile kill et"
        Write-Host "3) Tum SSH oturumlarini kill et"
        Write-Host "B) Geri don"
        Write-Host ""

        $choice = Read-Host "Secim yap"

        switch ($choice) {
            "1" { continue }
            "2" { Kill-SelectedSshSession }
            "3" { Kill-AllSshSessions }
            "B" { return }
            "b" { return }
            default {
                Write-Host "Gecersiz secim."
                Wait-Enter
            }
        }
    }
}
function Firewall-SetAllowedIps {
    $currentPort = Get-CurrentSshPort

    $ipInput = Read-Host "SSH icin izin verilecek IP adreslerini gir. Birden fazla IP icin virgulle ayir"

    $allowedIPs = $ipInput -split "," |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne "" }

    if (-not $allowedIPs -or $allowedIPs.Count -eq 0) {
        Write-Host "Gecerli IP adresi girilmedi."
        Wait-Enter
        return
    }

    $rule = Ensure-OpenSshFirewallRule -Port $currentPort

    Set-NetFirewallRule -Name $FirewallRuleName -Enabled True -Direction Inbound -Action Allow

    $portFilter = $rule | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
    if ($portFilter) {
        $portFilter | Set-NetFirewallPortFilter -Protocol TCP -LocalPort $currentPort
    }

    $addressFilter = $rule | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue
    if ($addressFilter) {
        $addressFilter | Set-NetFirewallAddressFilter -RemoteAddress $allowedIPs
    }

    Write-Host "SSH sadece su IP adreslerine izin verecek sekilde ayarlandi:"
    $allowedIPs

    Wait-Enter
}

function Firewall-AddAllowedIp {
    $currentPort = Get-CurrentSshPort

    $newIP = Read-Host "SSH izin listesine eklenecek IP adresini gir"

    if ([string]::IsNullOrWhiteSpace($newIP)) {
        Write-Host "Gecerli IP adresi girilmedi."
        Wait-Enter
        return
    }

    $rule = Ensure-OpenSshFirewallRule -Port $currentPort
    $addressFilter = $rule | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue

    if (-not $addressFilter) {
        Write-Host "Adres filtresi bulunamadi."
        Wait-Enter
        return
    }

    $currentAddresses = @($addressFilter.RemoteAddress)

    if ($currentAddresses -contains "Any") {
        Write-Host "Mevcut kural Any durumda. Yani herkes zaten izinli."
        $confirm = Read-Host "Any yerine sadece $newIP izinli olsun mu? E/H"

        if ($confirm -eq "E" -or $confirm -eq "e") {
            $addressFilter | Set-NetFirewallAddressFilter -RemoteAddress $newIP
            Write-Host "SSH sadece $newIP adresine izin verecek sekilde ayarlandi."
        }
        else {
            Write-Host "Islem iptal edildi."
        }

        Wait-Enter
        return
    }

    if ($currentAddresses -contains $newIP) {
        Write-Host "$newIP zaten izinli."
        Wait-Enter
        return
    }

    $updatedAddresses = @($currentAddresses + $newIP) |
        Where-Object { $_ -ne "" } |
        Select-Object -Unique

    $addressFilter | Set-NetFirewallAddressFilter -RemoteAddress $updatedAddresses

    Write-Host "$newIP SSH izin listesine eklendi."
    Write-Host "Guncel izinli IP adresleri:"
    $updatedAddresses

    Wait-Enter
}

function Firewall-RemoveAllowedIp {
    $removeIP = Read-Host "SSH izin listesinden kaldirilacak IP adresini gir"

    if ([string]::IsNullOrWhiteSpace($removeIP)) {
        Write-Host "Gecerli IP adresi girilmedi."
        Wait-Enter
        return
    }

    $rule = Get-NetFirewallRule -Name $FirewallRuleName -ErrorAction SilentlyContinue

    if (-not $rule) {
        Write-Host "OpenSSH firewall kurali bulunamadi."
        Wait-Enter
        return
    }

    $addressFilter = $rule | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue

    if (-not $addressFilter) {
        Write-Host "Adres filtresi bulunamadi."
        Wait-Enter
        return
    }

    $currentAddresses = @($addressFilter.RemoteAddress)

    if ($currentAddresses -contains "Any") {
        Write-Host "Mevcut kural Any durumda. Belirli IP kaldirilamaz cunku herkes izinli."
        Wait-Enter
        return
    }

    if (-not ($currentAddresses -contains $removeIP)) {
        Write-Host "$removeIP SSH izin listesinde bulunamadi."
        Wait-Enter
        return
    }

    $updatedAddresses = $currentAddresses |
        Where-Object { $_ -ne $removeIP }

    if (-not $updatedAddresses -or $updatedAddresses.Count -eq 0) {
        Write-Host "Bu IP kaldirilirsa izinli IP kalmayacak. Islem yapilmadi."
        Wait-Enter
        return
    }

    $addressFilter | Set-NetFirewallAddressFilter -RemoteAddress $updatedAddresses

    Write-Host "$removeIP SSH izin listesinden kaldirildi."
    Write-Host "Guncel izinli IP adresleri:"
    $updatedAddresses

    Wait-Enter
}

function Firewall-SetAny {
    $currentPort = Get-CurrentSshPort
    $rule = Ensure-OpenSshFirewallRule -Port $currentPort

    $addressFilter = $rule | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue

    if ($addressFilter) {
        $addressFilter | Set-NetFirewallAddressFilter -RemoteAddress Any
        Enable-NetFirewallRule -Name $FirewallRuleName
        Write-Host "SSH firewall kurali Any yapildi. Her IP firewall seviyesinde izinli."
    }
    else {
        Write-Host "Adres filtresi bulunamadi."
    }

    Wait-Enter
}

function Firewall-BlockIp {
    $currentPort = Get-CurrentSshPort

    $ip = Read-Host "SSH icin engellenecek IP adresini gir"

    if ([string]::IsNullOrWhiteSpace($ip)) {
        Write-Host "Gecerli IP adresi girilmedi."
        Wait-Enter
        return
    }

    $ruleName = "Block-SSH-$ip"
    $rule = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue

    if ($rule) {
        Write-Host "$ip icin engelleme kurali zaten var."
    }
    else {
        $params = @{
            Name          = $ruleName
            DisplayName   = "Block SSH from $ip"
            Enabled       = "True"
            Direction     = "Inbound"
            Action        = "Block"
            Protocol      = "TCP"
            LocalPort     = $currentPort
            RemoteAddress = $ip
        }

        New-NetFirewallRule @params | Out-Null
        Write-Host "$ip adresi SSH icin engellendi. Port: $currentPort"
    }

    Wait-Enter
}

function Firewall-RemoveBlockIp {
    $ip = Read-Host "SSH engeli kaldirilacak IP adresini gir"

    if ([string]::IsNullOrWhiteSpace($ip)) {
        Write-Host "Gecerli IP adresi girilmedi."
        Wait-Enter
        return
    }

    $ruleName = "Block-SSH-$ip"
    $rule = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue

    if ($rule) {
        Remove-NetFirewallRule -Name $ruleName
        Write-Host "$ip icin SSH engeli kaldirildi."
    }
    else {
        Write-Host "$ip icin engelleme kurali bulunamadi."
    }

    Wait-Enter
}

function Firewall-DisableRule {
    $ruleName = Read-Host "Pasif yapilacak firewall kuralinin Name degerini gir"

    $rule = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue

    if (-not $rule) {
        Write-Host "$ruleName isimli firewall kurali bulunamadi."
    }
    else {
        Disable-NetFirewallRule -Name $ruleName
        Write-Host "$ruleName isimli firewall kurali pasif yapildi."
    }

    Wait-Enter
}

function Firewall-EnableRule {
    $ruleName = Read-Host "Aktif yapilacak firewall kuralinin Name degerini gir"

    $rule = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue

    if (-not $rule) {
        Write-Host "$ruleName isimli firewall kurali bulunamadi."
    }
    else {
        Enable-NetFirewallRule -Name $ruleName
        Write-Host "$ruleName isimli firewall kurali aktif yapildi."
    }

    Wait-Enter
}

function Firewall-DeleteRule {
    $ruleName = Read-Host "Silinecek firewall kuralinin Name degerini gir"

    $rule = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue

    if (-not $rule) {
        Write-Host "$ruleName isimli firewall kurali bulunamadi."
        Wait-Enter
        return
    }

    Write-Host "Dikkat: $ruleName isimli firewall kurali silinecek."
    $confirm = Read-Host "Emin misin? E/H"

    if ($confirm -eq "E" -or $confirm -eq "e") {
        Remove-NetFirewallRule -Name $ruleName
        Write-Host "$ruleName isimli firewall kurali silindi."
    }
    else {
        Write-Host "Silme islemi iptal edildi."
    }

    Wait-Enter
}

function Firewall-Menu {
    while ($true) {
        Clear-Host
        Write-Host "=============================="
        Write-Host " SSH FIREWALL YONETIMI"
        Write-Host "=============================="
        Write-Host ""

        Show-SshFirewallRules

        Write-Host ""
        Write-Host "1) Firewall kurallarini yenile/listele"
        Write-Host "2) SSH icin sadece belirli IP/IP'lere izin ver"
        Write-Host "3) Mevcut SSH izin listesine yeni IP ekle"
        Write-Host "4) SSH izin listesinden IP kaldir"
        Write-Host "5) SSH izin kuralini tekrar Any yap"
        Write-Host "6) Belirli IP adresini SSH icin engelle"
        Write-Host "7) Belirli IP adresinin SSH engelini kaldir"
        Write-Host "8) Listelenen firewall kuralini pasif yap"
        Write-Host "9) Pasif firewall kuralini aktif yap"
        Write-Host "10) Listelenen firewall kuralini sil"
        Write-Host "B) Geri don"
        Write-Host ""

        $choice = Read-Host "Secim yap"

        switch ($choice) {
            "1" { continue }
            "2" { Firewall-SetAllowedIps }
            "3" { Firewall-AddAllowedIp }
            "4" { Firewall-RemoveAllowedIp }
            "5" { Firewall-SetAny }
            "6" { Firewall-BlockIp }
            "7" { Firewall-RemoveBlockIp }
            "8" { Firewall-DisableRule }
            "9" { Firewall-EnableRule }
            "10" { Firewall-DeleteRule }
            "B" { return }
            "b" { return }
            default {
                Write-Host "Gecersiz secim."
                Wait-Enter
            }
        }
    }
}

function Set-SshPort {
    $newPortInput = Read-Host "Yeni SSH portunu gir. Ornek: 2222"

    if (-not ($newPortInput -match '^\d+$')) {
        Write-Host "Gecersiz port. Sadece sayi gir."
        Wait-Enter
        return
    }

    $newPort = [int]$newPortInput

    if ($newPort -lt 1 -or $newPort -gt 65535) {
        Write-Host "Gecersiz port. Port 1 ile 65535 arasinda olmali."
        Wait-Enter
        return
    }

    $usedPort = Get-NetTCPConnection -LocalPort $newPort -State Listen -ErrorAction SilentlyContinue

    if ($usedPort) {
        Write-Host "Port $newPort su anda baska bir servis tarafindan dinleniyor."
        Wait-Enter
        return
    }

    Write-Host "SSH portu $newPort olarak ayarlanacak."
    Write-Host "Firewall OpenSSH kural portu da $newPort yapilacak."
    Write-Host "Yeni baglanti komutu: ssh kullanici@WindowsIP -p $newPort"

    $confirm = Read-Host "Devam edilsin mi? E/H"

    if ($confirm -ne "E" -and $confirm -ne "e") {
        Write-Host "Islem iptal edildi."
        Wait-Enter
        return
    }

    Backup-SshConfig | Out-Null
    Set-PortLineBeforeMatchBlock -NewPort $newPort

    $testOk = Test-SshConfig

    if (-not $testOk) {
        Write-Host "Config hatali olabilir. Servis restart edilmedi."
        Wait-Enter
        return
    }

    Set-SshFirewallPort -Port $newPort

    Restart-SshdSafe | Out-Null

    Write-Host "SSH portu $newPort olarak ayarlandi."
    Write-Host "Baglanti komutu: ssh kullanici@WindowsIP -p $newPort"

    Wait-Enter
}

function Restore-SshPort22 {
    Write-Host "SSH portu tekrar 22 yapilacak."
    $confirm = Read-Host "Devam edilsin mi? E/H"

    if ($confirm -ne "E" -and $confirm -ne "e") {
        Write-Host "Islem iptal edildi."
        Wait-Enter
        return
    }

    Backup-SshConfig | Out-Null
    Set-PortLineBeforeMatchBlock -NewPort 22

    $testOk = Test-SshConfig

    if (-not $testOk) {
        Write-Host "Config hatali olabilir. Servis restart edilmedi."
        Wait-Enter
        return
    }

    Set-SshFirewallPort -Port 22

    Restart-SshdSafe | Out-Null

    Write-Host "SSH portu tekrar 22 yapildi."
    Write-Host "Baglanti komutu: ssh kullanici@WindowsIP"

    Wait-Enter
}

function Open-SshConfigInNotepad {
    if (-not (Test-Path $ConfigPath)) {
        Write-Host "sshd_config bulunamadi: $ConfigPath"
        Wait-Enter
        return
    }

    Start-Process notepad.exe -ArgumentList $ConfigPath -Verb RunAs
    Write-Host "sshd_config Notepad ile acildi."
    Wait-Enter
}

function Show-ConnectCommand {
    $port = Get-CurrentSshPort

    Write-Host ""
    Write-Host "Linux / Kali / Ubuntu VM tarafindan baglanmak icin:"
    Write-Host ""

    if ($port -eq 22) {
        Write-Host "ssh kullanici@WindowsIP"
        Write-Host "Ornek: ssh administrator@192.168.56.1"
    }
    else {
        Write-Host "ssh kullanici@WindowsIP -p $port"
        Write-Host "Ornek: ssh administrator@192.168.56.1 -p $port"
    }

    Wait-Enter
}

function Config-Menu {
    while ($true) {
        Clear-Host

        $currentPort = Get-CurrentSshPort

        Write-Host "=============================="
        Write-Host " SSH PORT / CONFIG YONETIMI"
        Write-Host "=============================="
        Write-Host ""
        Write-Host "Config dosyasi: $ConfigPath"
        Write-Host "Aktif SSH portu: $currentPort"
        Write-Host ""

        Write-Host "1) SSH portunu degistir"
        Write-Host "2) SSH portunu tekrar 22 yap"
        Write-Host "3) sshd_config dosyasini Notepad ile ac"
        Write-Host "4) sshd_config dosyasini test et"
        Write-Host "5) Baglanti komutunu goster"
        Write-Host "6) sshd_config Port satirlarini analiz et"
        Write-Host "B) Geri don"
        Write-Host ""

        $choice = Read-Host "Secim yap"

        switch ($choice) {
            "1" { Set-SshPort }
            "2" { Restore-SshPort22 }
            "3" { Open-SshConfigInNotepad }
            "4" { Test-SshConfig | Out-Null; Wait-Enter }
            "5" { Show-ConnectCommand }
            "6" { Show-SshPortConfigLines }
            "B" { return }
            "b" { return }
            default {
                Write-Host "Gecersiz secim."
                Wait-Enter
            }
        }
    }
}

$exitPanel = $false

while (-not $exitPanel) {
    Show-Dashboard

    Write-Host ""
    Write-Host "======================================"
    Write-Host " ANA MENU"
    Write-Host "======================================"
    Write-Host "1) Durum ekranini yenile"
    Write-Host "2) SSH servis yonetimi"
    Write-Host "3) SSH port / config yonetimi"
    Write-Host "4) Baglanti komutunu goster"
    Write-Host "5) Aktif SSH oturumlarini listele / secileni kill et"
    Write-Host "6) SSH firewall kurallari yonetimi"
    Write-Host "Q) Cikis"
    Write-Host ""

    $mainChoice = Read-Host "Secim yap"

    switch ($mainChoice) {
        "1" { continue }
        "2" { Service-Menu }
        "3" { Config-Menu }
        "4" { Show-ConnectCommand }
        "5" { SshSession-Menu }
        "6" { Firewall-Menu }
        "Q" { $exitPanel = $true }
        "q" { $exitPanel = $true }
        default {
            Write-Host "Gecersiz secim."
            Wait-Enter
        }
    }
}
