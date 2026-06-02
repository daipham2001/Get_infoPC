// ============================================================
// Code.gs — Google Apps Script Web App
// Nhận POST từ PowerShell, ghi vào Google Sheets
//
// Hướng dẫn triển khai:
//   1. Mở Google Sheets → Extensions → Apps Script
//   2. Dán toàn bộ code này vào, xóa code mặc định
//   3. Đổi SECRET_KEY bên dưới thành chuỗi bí mật của bạn
//   4. Deploy → New deployment → Web app
//      - Execute as: Me
//      - Who has access: Anyone
//   5. Copy URL và dán vào PowerShell script
// ============================================================

var SECRET_KEY = "THAY_BANG_SECRET_KEY_CUA_BAN"; // Phải khớp với $SecretKey trong PowerShell
var SHEET_NAME = "Inventory";

// ============================================================
// HÀM CHÍNH — nhận POST từ PowerShell
// ============================================================
function doPost(e) {
  try {
    var data = JSON.parse(e.postData.contents);

    // 1. Xác thực secret token
    if (data.secret !== SECRET_KEY) {
      return jsonResponse({ status: "unauthorized", message: "Sai secret key" });
    }

    var ss    = SpreadsheetApp.getActiveSpreadsheet();
    var sheet = ss.getSheetByName(SHEET_NAME) || ss.insertSheet(SHEET_NAME);

    // 2. Tạo header nếu sheet trống
    if (sheet.getLastRow() === 0) {
      sheet.appendRow([
        "Lần cuối cập nhật", "Asset Tag", "Serial Number", "Computer Name",
        "Model Name", "Category", "Status", "User Đăng nhập",
        "IP Address", "MAC Address", "CPU", "RAM (GB)", "Ổ C (GB)", "UUID"
      ]);
      sheet.getRange(1, 1, 1, 14)
           .setFontWeight("bold")
           .setBackground("#4A86E8")
           .setFontColor("#FFFFFF");
      sheet.setFrozenRows(1);
    }

    // 3. Upsert — cập nhật nếu đã có UUID, thêm mới nếu chưa có
    var result = upsertRow(sheet, data);

    // 4. Ghi lịch sử thay đổi
    logHistory(ss, data, result);

    return jsonResponse({ status: "success", action: result });

  } catch (error) {
    logError(SpreadsheetApp.getActiveSpreadsheet(), error, e.postData ? e.postData.contents : "no data");
    return jsonResponse({ status: "error", message: error.toString() });
  }
}

// ============================================================
// UPSERT — cập nhật nếu trùng UUID, thêm mới nếu chưa có
// ============================================================
function upsertRow(sheet, data) {
  var uuid   = data.uuid;
  var newRow = [
    new Date(),    data.assetTag,  data.serial,    data.assetName,
    data.modelName, data.category, data.status,    data.assignedTo,
    data.ipAddress, data.macAddress, data.cpu,     data.ram,
    data.disk,     uuid
  ];

  // UUID nằm ở cột 14 (index 13)
  var values = sheet.getDataRange().getValues();
  for (var i = 1; i < values.length; i++) {
    if (values[i][13] === uuid) {
      sheet.getRange(i + 1, 1, 1, 14).setValues([newRow]);
      return "updated";
    }
  }

  sheet.appendRow(newRow);
  return "inserted";
}

// ============================================================
// LOG LỊCH SỬ — mỗi lần sync đều ghi vào sheet _history
// ============================================================
function logHistory(ss, data, action) {
  var histSheet = ss.getSheetByName("_history") || ss.insertSheet("_history");
  if (histSheet.getLastRow() === 0) {
    histSheet.appendRow(["Thời gian", "Action", "Computer Name", "User", "IP", "UUID"]);
    histSheet.getRange(1, 1, 1, 6).setFontWeight("bold");
  }
  histSheet.appendRow([new Date(), action, data.assetName, data.assignedTo, data.ipAddress, data.uuid]);
}

// ============================================================
// LOG LỖI — ghi lỗi vào sheet _errors để admin theo dõi
// ============================================================
function logError(ss, error, rawData) {
  var errSheet = ss.getSheetByName("_errors") || ss.insertSheet("_errors");
  if (errSheet.getLastRow() === 0) {
    errSheet.appendRow(["Thời gian", "Lỗi", "Raw Data"]);
    errSheet.getRange(1, 1, 1, 3)
            .setFontWeight("bold")
            .setBackground("#EA4335")
            .setFontColor("#FFFFFF");
  }
  errSheet.appendRow([new Date(), error.toString(), rawData]);
}

// ============================================================
// HELPER — trả JSON response
// ============================================================
function jsonResponse(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
                       .setMimeType(ContentService.MimeType.JSON);
}
