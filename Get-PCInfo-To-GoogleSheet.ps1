# ============================================================
# Get-PCInfo-To-GoogleSheet.ps1
# Thu thập cấu hình PC và đẩy lên Google Sheets qua Apps Script
#
# Cách dùng:
#   1. Đặt biến môi trường (khuyến nghị):
#      $env:GG_WEBAPP_URL  = "https://script.google.com/macros/s/.../exec"
#      $env:GG_SECRET_KEY  = "SecretKeyBiMatCuaBan"
#
#   2. Hoặc chỉnh trực tiếp 2 dòng bên dưới (không khuyến nghị cho môi trường nhiều máy)
# ============================================================

# 1. CẤU HÌNH
$GoogleWebAppUrl = if ($env:GG_WEBAPP_URL) { $env:GG_WEBAPP_URL } else { "DÁN_URL_WEB_APP_VÀO_ĐÂY" }
$SecretKey       = if ($env:GG_SECRET_KEY) { $env:GG_SECRET_KEY } else { "THAY_BANG_SECRET_KEY_CUA_BAN" }

# 2. Thông tin máy & user
$PCName = $env:COMPUTERNAME
$User   = $env:USERNAME

Write-Host "Đang thu thập thông tin máy [$PCName]..." -ForegroundColor Cyan

# 3. Lấy IP & MAC theo default gateway (chính xác hơn -First 1)
try {
    $ActiveRoute   = Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Sort-Object RouteMetric | Select-Object -First 1
    $IP            = (Get-NetIPAddress -InterfaceIndex $ActiveRoute.ifIndex -AddressFamily IPv4 -ErrorAction Stop).IPAddress
    $ActiveAdapter = Get-NetAdapter -InterfaceIndex $ActiveRoute.ifIndex -ErrorAction Stop
    $MAC           = $ActiveAdapter.MacAddress
} catch {
    Write-Warning "Không lấy được thông tin mạng qua default gateway. Dùng fallback..."
    $IP  = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Wi-Fi","Ethernet" -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress
    $MAC = (Get-NetAdapter | Where-Object Status -eq "Up" | Select-Object -First 1).MacAddress
    if (-not $IP)  { $IP  = "Không lấy được IP" }
    if (-not $MAC) { $MAC = "Không lấy được MAC" }
}

# 4. Thông tin phần cứng
$CPU     = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
$RAM_GB  = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
$Disk_C  = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$Disk_GB = if ($Disk_C) { [math]::Round($Disk_C.Size / 1GB, 1) } else { "N/A" }
$UUID    = (Get-CimInstance Win32_ComputerSystemProduct).UUID

# 5. Model name từ Baseboard (tốt hơn hardcode "Custom Build PC")
try {
    $Board     = Get-CimInstance Win32_BaseBoard
    $ModelName = "$($Board.Manufacturer) $($Board.Product)".Trim()
    if ([string]::IsNullOrWhiteSpace($ModelName) -or $ModelName -eq " ") {
        $ModelName = "Custom Build"
    }
} catch {
    $ModelName = "Custom Build"
}

# 6. Serial Number — fallback về MAC nếu giá trị là rác
$SN = (Get-CimInstance Win32_BIOS).SerialNumber
if ([string]::IsNullOrWhiteSpace($SN) -or $SN -match "Default|O\.E\.M|To be filled|Not Specified|None") {
    $SN = "MAC-$MAC"
}

# 7. Đóng gói JSON
$Body = @{
    secret     = $SecretKey
    assetTag   = "PC-$PCName"
    serial     = $SN
    assetName  = $PCName
    modelName  = $ModelName
    category   = "Desktops"
    status     = "Deployed"
    assignedTo = $User
    ipAddress  = $IP
    macAddress = $MAC
    cpu        = $CPU
    ram        = $RAM_GB
    disk       = $Disk_GB
    uuid       = $UUID
} | ConvertTo-Json -Compress

# 8. Gửi lên Google Sheets
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $Response = Invoke-RestMethod -Uri $GoogleWebAppUrl `
                                  -Method Post `
                                  -Body $Body `
                                  -ContentType "application/json; charset=utf-8"

    switch ($Response.status) {
        "success" {
            $Action = if ($Response.action -eq "updated") { "Cập nhật" } else { "Thêm mới" }
            Write-Host "--------------------------------------------------------" -ForegroundColor Green
            Write-Host "[$Action] Đã đồng bộ máy [$PCName] lên Google Sheet!" -ForegroundColor Green
            Write-Host "--------------------------------------------------------" -ForegroundColor Green
        }
        "unauthorized" {
            Write-Warning "Sai Secret Key — kiểm tra lại cấu hình GG_SECRET_KEY."
        }
        default {
            Write-Warning "Lỗi từ server: $($Response.message)"
        }
    }
} catch {
    Write-Error "Không kết nối được Google. Kiểm tra mạng Internet. Chi tiết: $_"
}

Start-Sleep -Seconds 3
