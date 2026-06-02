# Get_infoPC

Script PowerShell thu thập toàn diện thông tin phần cứng, hệ thống và bảo mật của máy PC, đẩy tự động lên Google Sheets qua HTTPS — không cần server trung gian, không cần VPN, vượt qua firewall.

## Kiến trúc

```
Máy PC (PowerShell)
       │
       │ HTTPS POST (Port 443)
       ▼
Google Apps Script (Web App)
       │
       ▼
Google Sheets
  ├── Inventory    ← dữ liệu chính, upsert theo UUID
  ├── _history     ← log mỗi lần sync
  └── _errors      ← log lỗi
       │
       ▼ Export CSV
Snipe-IT (import thủ công)
```

## Dữ liệu thu thập

| Nhóm | Thông tin |
|------|-----------|
| **Định danh** | Asset Tag (từ BIOS/Chassis), Serial Number (BIOS → Mainboard → Chassis → fallback), Computer Name, Model, UUID |
| **Mạng** | IP chính, MAC chính, tất cả IP/MAC các adapter, WiFi SSID, Domain/Workgroup |
| **CPU** | Tên, số nhân/luồng |
| **RAM** | Tổng GB, loại DDR4/DDR5, tốc độ MHz, số thanh |
| **GPU** | Tên card, VRAM |
| **Màn hình** | Số lượng, tên model, độ phân giải |
| **Ổ cứng** | Tất cả ổ — dung lượng, còn trống, loại SSD/HDD |
| **Nhiệt độ** | CPU & GPU — cần OpenHardwareMonitor (xem bên dưới) |
| **Windows** | Phiên bản, Build, kiến trúc, bản update cuối |
| **Phần mềm** | Office, Antivirus, danh sách app đã cài |
| **Bảo mật** | BitLocker (C:), Firewall theo từng profile |

### Thứ tự ưu tiên lấy Serial Number

Script thử lần lượt, lấy giá trị đầu tiên không phải rác:

```
BIOS Serial → Mainboard Serial → Chassis Serial → NO-SN-<TênMáy>
```

Tương tự với Asset Tag:

```
SMBIOSAssetTag (Chassis) → IdentifyingNumber (Product) → PC-<TênMáy>
```

Phù hợp với cả máy hãng (Dell/HP/Lenovo) lẫn PC lắp ráp.

## Yêu cầu

- Windows 7 trở lên, PowerShell 5.0+
- Kết nối Internet (HTTPS port 443)
- Một số tính năng cần **chạy với quyền Administrator**: BitLocker, loại ổ cứng (SSD/HDD), Antivirus

## Hướng dẫn triển khai

### Bước 1 — Tạo Google Apps Script

1. Tạo một file **Google Sheets** mới trên Drive
2. Vào menu **Extensions → Apps Script**
3. Xóa code mặc định, dán toàn bộ nội dung file `Code.gs` vào
4. Đổi giá trị `SECRET_KEY` thành chuỗi bí mật của bạn (ví dụ: `Kho@XuongABC2024!`)
5. Nhấn **Deploy → New deployment**
   - Chọn loại: **Web app**
   - Execute as: **Me**
   - Who has access: **Anyone**
6. Nhấn **Deploy**, cấp quyền khi được hỏi
7. Copy **Web App URL** (dạng `https://script.google.com/macros/s/.../exec`)

> **Lưu ý:** Mỗi lần chỉnh sửa `Code.gs` phải **Deploy lại** (New deployment) thì thay đổi mới có hiệu lực.

### Bước 2 — Cấu hình PowerShell script

Mở file `Get-PCInfo-To-GoogleSheet.ps1`, chỉnh 2 dòng đầu:

```powershell
$GoogleWebAppUrl = "https://script.google.com/macros/s/.../exec"  # URL từ Bước 1
$SecretKey       = "Kho@XuongABC2024!"                            # Phải khớp với Code.gs
```

Hoặc dùng biến môi trường (khuyến nghị cho môi trường nhiều máy):

```powershell
$env:GG_WEBAPP_URL = "https://script.google.com/macros/s/.../exec"
$env:GG_SECRET_KEY = "Kho@XuongABC2024!"
```

### Bước 3 — Chạy script

```powershell
powershell -ExecutionPolicy Bypass -File .\Get-PCInfo-To-GoogleSheet.ps1
```

Kết quả trả về:
- `[Thêm mới]` — máy chưa có trong sheet, tạo dòng mới
- `[Cập nhật]` — máy đã có (theo UUID), cập nhật dòng cũ

### Bước 4 — Lấy nhiệt độ CPU/GPU (tùy chọn)

Script đọc nhiệt độ qua WMI từ **OpenHardwareMonitor**. Nếu không cài, cột nhiệt độ tự động ghi `N/A` và script vẫn chạy bình thường.

Để bật tính năng này:
1. Tải [OpenHardwareMonitor](https://openhardwaremonitor.org/)
2. Giải nén, chạy `OpenHardwareMonitor.exe` với quyền **Administrator**
3. Vào **Options → Start Minimized** và **Options → Run On Windows Startup**

### Bước 5 — Tự động chạy khi đăng nhập (tùy chọn)

Chạy đoạn sau với quyền Administrator để đăng ký Scheduled Task:

```powershell
$Action  = New-ScheduledTaskAction `
               -Execute "powershell.exe" `
               -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Tools\Get-PCInfo-To-GoogleSheet.ps1"
$Trigger = New-ScheduledTaskTrigger -AtLogOn
Register-ScheduledTask -TaskName "PC Inventory Sync" `
    -Action $Action -Trigger $Trigger -RunLevel Highest -Force
```

## Xuất sang Snipe-IT

Trong Google Sheets: **File → Download → Comma Separated Values (.csv)** rồi import vào Snipe-IT.

> Nếu Snipe-IT được dựng trên server/VPS có địa chỉ public, có thể bỏ qua Google Sheets và đẩy thẳng từ PowerShell lên Snipe-IT API.

## Bảo mật

- Secret Key xác thực từng request — sai key sẽ bị từ chối, không ghi dữ liệu
- Không lưu thông tin tài khoản Google trên máy client
- Kết nối HTTPS, ép TLS 1.2 (tương thích Windows cũ)
- Không commit Secret Key lên repository — dùng biến môi trường hoặc file config riêng nằm trong `.gitignore`

## Cấu trúc file

```
Get_infoPC/
├── Get-PCInfo-To-GoogleSheet.ps1   # Script chạy trên máy client
├── Code.gs                         # Dán vào Google Apps Script
├── README.md
└── .gitignore
```
