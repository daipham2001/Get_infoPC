# ============================================================
# Get-PCInfo-To-GoogleSheet.ps1 — v2.0
# Thu thập toàn diện cấu hình PC và đẩy lên Google Sheets
#
# Cách dùng:
#   Đặt biến môi trường (khuyến nghị):
#     $env:GG_WEBAPP_URL = "https://script.google.com/macros/s/.../exec"
#     $env:GG_SECRET_KEY = "SecretKeyBiMatCuaBan"
#
#   Hoặc chỉnh trực tiếp 2 dòng đầu bên dưới.
#
# Lưu ý — Nhiệt độ CPU/GPU:
#   Cần OpenHardwareMonitor đang chạy ở background (chạy 1 lần với quyền Admin).
#   Tải tại: https://openhardwaremonitor.org/
#   Nếu không có → script vẫn chạy bình thường, cột nhiệt độ ghi "N/A".
# ============================================================

# ── CẤU HÌNH ─────────────────────────────────────────────────
$GoogleWebAppUrl = if ($env:GG_WEBAPP_URL) { $env:GG_WEBAPP_URL } else { "DÁN_URL_WEB_APP_VÀO_ĐÂY" }
$SecretKey       = if ($env:GG_SECRET_KEY) { $env:GG_SECRET_KEY } else { "THAY_BANG_SECRET_KEY_CUA_BAN" }

Write-Host "================================================" -ForegroundColor Cyan
Write-Host " PC INVENTORY SYNC v2.0" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

# ── 1. THÔNG TIN CƠ BẢN ──────────────────────────────────────
$PCName = $env:COMPUTERNAME
$User   = $env:USERNAME
Write-Host "[1/9] Thông tin cơ bản..." -ForegroundColor Yellow

# ── 2. MẠNG — IP & MAC tất cả adapter đang UP ────────────────
Write-Host "[2/9] Thông tin mạng..." -ForegroundColor Yellow
try {
    # Default gateway adapter (IP chính)
    $ActiveRoute   = Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Sort-Object RouteMetric | Select-Object -First 1
    $PrimaryIP     = (Get-NetIPAddress -InterfaceIndex $ActiveRoute.ifIndex -AddressFamily IPv4 -ErrorAction Stop).IPAddress
    $PrimaryMAC    = (Get-NetAdapter -InterfaceIndex $ActiveRoute.ifIndex -ErrorAction Stop).MacAddress
} catch {
    $PrimaryIP  = "N/A"
    $PrimaryMAC = "N/A"
}

# Tất cả IP/MAC của các adapter đang UP
$AllAdapters = Get-NetAdapter | Where-Object Status -eq "Up"
$AllIPsMACs  = $AllAdapters | ForEach-Object {
    $adapter = $_
    $ip = (Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
    if ($ip) { "$($adapter.Name): $ip / $($adapter.MacAddress)" }
}
$AllNetworkInfo = ($AllIPsMACs -join " | ")

# WiFi SSID
try {
    $WifiSSID = (netsh wlan show interfaces | Select-String "SSID" | Where-Object { $_ -notmatch "BSSID" } | Select-Object -First 1) -replace ".*SSID\s+:\s+", ""
    $WifiSSID = $WifiSSID.Trim()
    if ([string]::IsNullOrWhiteSpace($WifiSSID)) { $WifiSSID = "Không kết nối WiFi" }
} catch {
    $WifiSSID = "N/A"
}

# Domain hay Workgroup
$SysInfo    = Get-CimInstance Win32_ComputerSystem
$DomainInfo = if ($SysInfo.PartOfDomain) { "Domain: $($SysInfo.Domain)" } else { "Workgroup: $($SysInfo.Workgroup)" }

# ── 3. CPU ───────────────────────────────────────────────────
Write-Host "[3/9] CPU..." -ForegroundColor Yellow
$CPUObj  = Get-CimInstance Win32_Processor | Select-Object -First 1
$CPUName = $CPUObj.Name.Trim()
$CPUCores= "$($CPUObj.NumberOfCores)C/$($CPUObj.NumberOfLogicalProcessors)T"

# ── 4. RAM — loại, tốc độ, số thanh ─────────────────────────
Write-Host "[4/9] RAM..." -ForegroundColor Yellow
$RAM_GB    = [math]::Round($SysInfo.TotalPhysicalMemory / 1GB, 1)
$RAMSlots  = Get-CimInstance Win32_PhysicalMemory
$RAMDetail = $RAMSlots | ForEach-Object {
    $type = switch ($_.SMBIOSMemoryType) {
        26 { "DDR4" } 34 { "DDR5" } 24 { "DDR3" } default { "DDR?" }
    }
    "$($_.Capacity/1GB)GB $type @$($_.Speed)MHz"
}
$RAMInfo   = ($RAMDetail -join " | ")
$RAMSlotCount = "$($RAMSlots.Count) thanh"

# ── 5. GPU ───────────────────────────────────────────────────
Write-Host "[5/9] GPU..." -ForegroundColor Yellow
$GPUs    = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch "Microsoft|Remote" }
$GPUInfo = ($GPUs | ForEach-Object {
    $vram = if ($_.AdapterRAM -gt 0) { "$([math]::Round($_.AdapterRAM/1GB,1))GB" } else { "N/A VRAM" }
    "$($_.Name) ($vram)"
} | Select-Object -First 3) -join " | "
if ([string]::IsNullOrWhiteSpace($GPUInfo)) { $GPUInfo = "Integrated/N/A" }

# ── 6. MÀN HÌNH ─────────────────────────────────────────────
Write-Host "[6/9] Màn hình..." -ForegroundColor Yellow
try {
    $Monitors = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop
    $MonitorDetails = $Monitors | ForEach-Object {
        $name = [System.Text.Encoding]::ASCII.GetString($_.UserFriendlyName -ne 0).Trim()
        if ([string]::IsNullOrWhiteSpace($name)) { $name = "Unknown Monitor" }
        $name
    }
    $MonitorCount = $Monitors.Count
    $MonitorInfo  = "$MonitorCount màn: " + ($MonitorDetails -join ", ")
} catch {
    $MonitorCount = "N/A"
    $MonitorInfo  = "Không lấy được"
}

# Độ phân giải màn hình chính
try {
    $Resolution = (Get-CimInstance Win32_VideoController | Select-Object -First 1)
    $ResInfo    = "$($Resolution.CurrentHorizontalResolution)x$($Resolution.CurrentVerticalResolution)"
} catch {
    $ResInfo = "N/A"
}

# ── 7. Ổ CỨNG TẤT CẢ ────────────────────────────────────────
Write-Host "[7/9] Ổ cứng..." -ForegroundColor Yellow
$AllDisks = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
$DiskInfo = ($AllDisks | ForEach-Object {
    $total = [math]::Round($_.Size / 1GB, 1)
    $free  = [math]::Round($_.FreeSpace / 1GB, 1)
    "$($_.DeviceID) $($total)GB (còn $($free)GB)"
}) -join " | "
$Disk_C_GB = if ($AllDisks | Where-Object { $_.DeviceID -eq "C:" }) {
    [math]::Round(($AllDisks | Where-Object { $_.DeviceID -eq "C:" }).Size / 1GB, 1)
} else { "N/A" }

# Loại ổ (SSD/HDD) — cần quyền Admin
try {
    $PhysicalDisks = Get-PhysicalDisk -ErrorAction Stop
    $DiskTypes     = ($PhysicalDisks | ForEach-Object { "$($_.FriendlyName): $($_.MediaType)" }) -join " | "
} catch {
    $DiskTypes = "Cần quyền Admin để xem"
}

# ── 8. HỆ THỐNG & PHẦN MỀM ──────────────────────────────────
Write-Host "[8/9] Hệ thống & phần mềm..." -ForegroundColor Yellow

# Windows version
$WinVer   = (Get-CimInstance Win32_OperatingSystem)
$WinInfo  = "$($WinVer.Caption) (Build $($WinVer.BuildNumber)) — $($WinVer.OSArchitecture)"

# Windows Update — bản update cuối cùng
try {
    $LastUpdate = (Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1)
    $WinUpdate  = "KB: $($LastUpdate.HotFixID) — $($LastUpdate.InstalledOn.ToString('dd/MM/yyyy'))"
} catch {
    $WinUpdate = "Không lấy được"
}

# Microsoft Office
try {
    $OfficePath = @(
        "HKLM:\SOFTWARE\Microsoft\Office",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office"
    )
    $OfficeVer = $OfficePath | ForEach-Object {
        if (Test-Path $_) { Get-ChildItem $_ | Where-Object { $_.Name -match "\d+\.\d+" } | Select-Object -Last 1 }
    } | Select-Object -First 1
    $OfficeInfo = if ($OfficeVer) {
        $ver = ($OfficeVer.Name -split "\\")[-1]
        $map = @{"16.0"="Office 2016/2019/2021/365";"15.0"="Office 2013";"14.0"="Office 2010"}
        if ($map[$ver]) { $map[$ver] } else { "Office (v$ver)" }
    } else { "Không cài Office" }
} catch {
    $OfficeInfo = "N/A"
}

# Antivirus
try {
    $AV = Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop
    $AVInfo = ($AV | ForEach-Object { $_.displayName }) -join ", "
    if ([string]::IsNullOrWhiteSpace($AVInfo)) { $AVInfo = "Không phát hiện AV" }
} catch {
    $AVInfo = "N/A (cần quyền Admin)"
}

# Danh sách phần mềm đã cài (top phổ biến, tránh list quá dài)
try {
    $RegPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    $InstalledApps = $RegPaths | ForEach-Object {
        Get-ItemProperty $_ -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and $_.DisplayName -notmatch "^KB\d+" -and $_.SystemComponent -ne 1 } |
        Select-Object DisplayName, DisplayVersion
    }
    $AppList = ($InstalledApps | Sort-Object DisplayName -Unique |
        Select-Object -First 50 |
        ForEach-Object { "$($_.DisplayName) $($_.DisplayVersion)" }) -join "; "
} catch {
    $AppList = "Không lấy được"
}

# ── 9. BẢO MẬT ──────────────────────────────────────────────
Write-Host "[9/9] Bảo mật..." -ForegroundColor Yellow

# BitLocker
try {
    $BL = Get-BitLockerVolume -MountPoint "C:" -ErrorAction Stop
    $BitLockerStatus = $BL.ProtectionStatus  # On / Off
} catch {
    try {
        $BLInfo = manage-bde -status C: 2>$null
        $BitLockerStatus = if ($BLInfo -match "Protection On") { "On" } else { "Off" }
    } catch {
        $BitLockerStatus = "N/A"
    }
}

# Firewall
try {
    $FW = Get-NetFirewallProfile -ErrorAction Stop
    $FirewallStatus = ($FW | ForEach-Object { "$($_.Name): $(if($_.Enabled){'On'}else{'Off'})" }) -join " | "
} catch {
    $FirewallStatus = "N/A"
}

# ── NHIỆT ĐỘ (qua OpenHardwareMonitor WMI) ──────────────────
try {
    $OHM     = Get-CimInstance -Namespace "root\OpenHardwareMonitor" -ClassName Sensor -ErrorAction Stop |
               Where-Object { $_.SensorType -eq "Temperature" }
    $CpuTemp = ($OHM | Where-Object { $_.Name -match "CPU|Package" } | Select-Object -First 1).Value
    $GpuTemp = ($OHM | Where-Object { $_.Name -match "GPU" } | Select-Object -First 1).Value
    $TempInfo = "CPU: ${CpuTemp}°C | GPU: ${GpuTemp}°C"
} catch {
    $TempInfo = "N/A (cần OpenHardwareMonitor)"
}

# ── SN, ASSET TAG & MODEL ────────────────────────────────────
$UUID = (Get-CimInstance Win32_ComputerSystemProduct).UUID

# Hàm kiểm tra giá trị rác từ BIOS
$IsJunk = { param($s) [string]::IsNullOrWhiteSpace($s) -or $s -match "Default|O\.E\.M|To be filled|Not Specified|None|^\s*$|^0+$" }

# Serial Number — lấy theo thứ tự ưu tiên
$SN_BIOS    = (Get-CimInstance Win32_BIOS).SerialNumber
$SN_Board   = (Get-CimInstance Win32_BaseBoard).SerialNumber
$SN_Chassis = (Get-CimInstance Win32_SystemEnclosure).SerialNumber

$SN = if     (-not (&$IsJunk $SN_BIOS))    { $SN_BIOS }
      elseif (-not (&$IsJunk $SN_Board))    { "Board: $SN_Board" }
      elseif (-not (&$IsJunk $SN_Chassis))  { "Chassis: $SN_Chassis" }
      else                                   { "NO-SN-$PCName" }

# Asset Tag — lấy từ BIOS/Chassis, fallback về Computer Name
$AT_BIOS    = (Get-CimInstance Win32_SystemEnclosure).SMBIOSAssetTag
$AT_Product = (Get-CimInstance Win32_ComputerSystemProduct).IdentifyingNumber

$AssetTag = if     (-not (&$IsJunk $AT_BIOS))    { $AT_BIOS }
            elseif (-not (&$IsJunk $AT_Product))  { $AT_Product }
            else                                   { "PC-$PCName" }

$Board     = Get-CimInstance Win32_BaseBoard
$ModelName = "$($Board.Manufacturer) $($Board.Product)".Trim()
if ([string]::IsNullOrWhiteSpace($ModelName) -or $ModelName -eq " ") { $ModelName = "Custom Build" }

# ── ĐÓNG GÓI JSON ────────────────────────────────────────────
$Body = @{
    secret          = $SecretKey
    # Định danh
    assetTag        = $AssetTag
    serial          = $SN
    assetName       = $PCName
    modelName       = $ModelName
    category        = "Desktops"
    status          = "Deployed"
    assignedTo      = $User
    uuid            = $UUID
    # Mạng
    ipAddress       = $PrimaryIP
    macAddress      = $PrimaryMAC
    allNetworkInfo  = $AllNetworkInfo
    wifiSSID        = $WifiSSID
    domainInfo      = $DomainInfo
    # Phần cứng
    cpu             = "$CPUName ($CPUCores)"
    ram             = $RAM_GB
    ramDetail       = $RAMInfo
    ramSlots        = $RAMSlotCount
    gpu             = $GPUInfo
    monitorInfo     = $MonitorInfo
    resolution      = $ResInfo
    disk            = $Disk_C_GB
    allDisks        = $DiskInfo
    diskTypes       = $DiskTypes
    temperature     = $TempInfo
    # Hệ thống
    windowsVersion  = $WinInfo
    windowsUpdate   = $WinUpdate
    officeVersion   = $OfficeInfo
    antivirus       = $AVInfo
    installedApps   = $AppList
    # Bảo mật
    bitlocker       = $BitLockerStatus.ToString()
    firewall        = $FirewallStatus
} | ConvertTo-Json -Compress

# ── GỬI LÊN GOOGLE SHEETS ────────────────────────────────────
Write-Host ""
Write-Host "Đang gửi dữ liệu lên Google Sheets..." -ForegroundColor Cyan
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $Response = Invoke-RestMethod -Uri $GoogleWebAppUrl `
                                  -Method Post `
                                  -Body $Body `
                                  -ContentType "application/json; charset=utf-8"

    switch ($Response.status) {
        "success" {
            $Action = if ($Response.action -eq "updated") { "Cập nhật" } else { "Thêm mới" }
            Write-Host "================================================" -ForegroundColor Green
            Write-Host " [$Action] Đã đồng bộ [$PCName] lên Google Sheet!" -ForegroundColor Green
            Write-Host "================================================" -ForegroundColor Green
        }
        "unauthorized" { Write-Warning "Sai Secret Key — kiểm tra lại GG_SECRET_KEY." }
        default         { Write-Warning "Lỗi server: $($Response.message)" }
    }
} catch {
    Write-Error "Không kết nối được Google. Kiểm tra mạng. Chi tiết: $_"
}

Start-Sleep -Seconds 4
