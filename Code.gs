// ============================================================
// Code.gs — Google Apps Script Web App v2.0
// ============================================================

var SECRET_KEY = "THAY_BANG_SECRET_KEY_CUA_BAN";
var SHEET_NAME = "Inventory";

function doPost(e) {
  try {
    var data = JSON.parse(e.postData.contents);

    if (data.secret !== SECRET_KEY) {
      return jsonResponse({ status: "unauthorized", message: "Sai secret key" });
    }

    var ss    = SpreadsheetApp.getActiveSpreadsheet();
    var sheet = ss.getSheetByName(SHEET_NAME) || ss.insertSheet(SHEET_NAME);

    if (sheet.getLastRow() === 0) {
      var headers = [
        // Định danh
        "Cập nhật lần cuối", "Asset Tag", "Serial Number", "Computer Name", "Model Name",
        "Category", "Status", "User Đăng nhập", "UUID",
        // Mạng
        "IP Chính", "MAC Chính", "Tất cả IP/MAC", "WiFi SSID", "Domain/Workgroup",
        // Phần cứng
        "CPU", "RAM (GB)", "RAM Chi tiết", "Số thanh RAM",
        "GPU", "Màn hình", "Độ phân giải",
        "Ổ C (GB)", "Tất cả ổ cứng", "Loại ổ cứng", "Nhiệt độ",
        // Hệ thống
        "Windows", "Windows Update", "Office", "Antivirus", "Phần mềm đã cài",
        // Bảo mật
        "BitLocker", "Firewall"
      ];
      sheet.appendRow(headers);
      sheet.getRange(1, 1, 1, headers.length)
           .setFontWeight("bold")
           .setBackground("#1a73e8")
           .setFontColor("#FFFFFF");
      sheet.setFrozenRows(1);

      // Cố định độ rộng cột hợp lý
      sheet.setColumnWidth(1, 160);  // Cập nhật lần cuối
      sheet.setColumnWidth(9, 280);  // UUID
      sheet.setColumnWidth(12, 300); // Tất cả IP/MAC
      sheet.setColumnWidth(23, 350); // Tất cả ổ cứng
      sheet.setColumnWidth(29, 400); // Phần mềm đã cài
    }

    var result = upsertRow(sheet, data);
    logHistory(ss, data, result);

    return jsonResponse({ status: "success", action: result });

  } catch (error) {
    logError(SpreadsheetApp.getActiveSpreadsheet(), error, e.postData ? e.postData.contents : "no data");
    return jsonResponse({ status: "error", message: error.toString() });
  }
}

function upsertRow(sheet, data) {
  var uuid   = data.uuid;
  var newRow = [
    // Định danh
    new Date(),         data.assetTag,      data.serial,        data.assetName,
    data.modelName,     data.category,      data.status,        data.assignedTo,    data.uuid,
    // Mạng
    data.ipAddress,     data.macAddress,    data.allNetworkInfo, data.wifiSSID,     data.domainInfo,
    // Phần cứng
    data.cpu,           data.ram,           data.ramDetail,     data.ramSlots,
    data.gpu,           data.monitorInfo,   data.resolution,
    data.disk,          data.allDisks,      data.diskTypes,     data.temperature,
    // Hệ thống
    data.windowsVersion, data.windowsUpdate, data.officeVersion, data.antivirus,   data.installedApps,
    // Bảo mật
    data.bitlocker,     data.firewall
  ];

  // UUID ở cột 9 (index 8)
  var values = sheet.getDataRange().getValues();
  for (var i = 1; i < values.length; i++) {
    if (values[i][8] === uuid) {
      sheet.getRange(i + 1, 1, 1, newRow.length).setValues([newRow]);
      return "updated";
    }
  }

  sheet.appendRow(newRow);
  return "inserted";
}

function logHistory(ss, data, action) {
  var h = ss.getSheetByName("_history") || ss.insertSheet("_history");
  if (h.getLastRow() === 0) {
    h.appendRow(["Thời gian", "Action", "Computer Name", "User", "IP", "Windows", "UUID"]);
    h.getRange(1, 1, 1, 7).setFontWeight("bold");
  }
  h.appendRow([new Date(), action, data.assetName, data.assignedTo, data.ipAddress, data.windowsVersion, data.uuid]);
}

function logError(ss, error, rawData) {
  var e = ss.getSheetByName("_errors") || ss.insertSheet("_errors");
  if (e.getLastRow() === 0) {
    e.appendRow(["Thời gian", "Lỗi", "Raw Data"]);
    e.getRange(1, 1, 1, 3).setFontWeight("bold").setBackground("#EA4335").setFontColor("#FFFFFF");
  }
  e.appendRow([new Date(), error.toString(), rawData]);
}

function jsonResponse(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
                       .setMimeType(ContentService.MimeType.JSON);
}
