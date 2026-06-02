# Get_infoPC — Thu thập thông tin PC → Google Sheets

Giải pháp thu thập cấu hình phần cứng từ nhiều máy PC và đẩy tự động lên Google Sheets qua HTTPS — không cần server, không cần VPN, vượt qua firewall.

## Kiến trúc

```
Máy PC (PowerShell) ──HTTPS POST──► Google Apps Script ──► Google Sheets
                                         (Web App)              ↓
                                                           Export CSV
                                                               ↓
                                                           Snipe-IT
```

## Tính năng

- **Upsert thông minh** — chạy lại trên cùng máy sẽ cập nhật dòng cũ, không tạo trùng
- **Xác thực Secret Key** — bảo vệ endpoint khỏi ghi rác
- **Lấy IP/MAC chính xác** theo default gateway
- **Tự động nhận diện model** từ Baseboard (phù hợp PC lắp ráp)
- **Serial Number fallback** về MAC nếu BIOS trả về giá trị rác
- **Log lịch sử** mỗi lần sync vào sheet `_history`
- **Log lỗi** vào sheet `_errors` để admin theo dõi

## Các file

| File | Mô tả |
|------|-------|
| `Get-PCInfo-To-GoogleSheet.ps1` | Chạy trên máy client (Windows PowerShell) |
| `Code.gs` | Dán vào Google Apps Script |

## Hướng dẫn triển khai

### Bước 1 — Cài đặt Google Apps Script

1. Tạo file **Google Sheets** mới
2. Vào **Extensions → Apps Script**
3. Xóa code mặc định, dán toàn bộ nội dung `Code.gs` vào
4. Đổi `SECRET_KEY` thành chuỗi bí mật của bạn (ví dụ: `Kho@XuongABC2024!`)
5. **Deploy → New deployment → Web app**
   - Execute as: **Me**
   - Who has access: **Anyone**
6. Nhấn **Deploy**, cấp quyền khi được hỏi
7. Copy **Web App URL**

### Bước 2 — Cấu hình PowerShell

Có 2 cách đặt cấu hình (khuyến nghị dùng biến môi trường):

**Cách 1 — Biến môi trường (khuyến nghị):**
```powershell
$env:GG_WEBAPP_URL = "https://script.google.com/macros/s/.../exec"
$env:GG_SECRET_KEY = "Kho@XuongABC2024!"
```

**Cách 2 — Chỉnh trực tiếp trong file .ps1:**
```powershell
$GoogleWebAppUrl = "https://script.google.com/macros/s/.../exec"
$SecretKey       = "Kho@XuongABC2024!"
```

### Bước 3 — Chạy script

```powershell
powershell -ExecutionPolicy Bypass -File .\Get-PCInfo-To-GoogleSheet.ps1
```

### Bước 4 — Tự động hóa (tùy chọn)

Đăng ký Scheduled Task để chạy mỗi khi người dùng đăng nhập:

```powershell
$Action  = New-ScheduledTaskAction -Execute "powershell.exe" `
               -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Tools\Get-PCInfo-To-GoogleSheet.ps1"
$Trigger = New-ScheduledTaskTrigger -AtLogOn
Register-ScheduledTask -TaskName "PC Inventory Sync" `
    -Action $Action -Trigger $Trigger -RunLevel Highest -Force
```

## Cấu trúc Google Sheets

Sheet **Inventory** (dữ liệu chính):

| Cột | Nội dung |
|-----|----------|
| A | Lần cuối cập nhật |
| B | Asset Tag |
| C | Serial Number |
| D | Computer Name |
| E | Model Name |
| F | Category |
| G | Status |
| H | User Đăng nhập |
| I | IP Address |
| J | MAC Address |
| K | CPU |
| L | RAM (GB) |
| M | Ổ C (GB) |
| N | UUID |

Sheet **_history** — lịch sử mỗi lần sync  
Sheet **_errors** — log lỗi nếu có

## Bảo mật

- Secret Key được so khớp ở phía Apps Script trước khi ghi dữ liệu
- Không lưu thông tin tài khoản Google trên máy client
- Kết nối qua HTTPS (TLS 1.2)
- **Không commit Secret Key lên GitHub** — dùng biến môi trường hoặc file config riêng

## Xuất dữ liệu sang Snipe-IT

Trong Google Sheets: **File → Download → Comma Separated Values (.csv)**  
Sau đó import file CSV vào Snipe-IT.
