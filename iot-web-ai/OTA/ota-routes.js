// OTA/ota-routes.js - ESP8266/ESP12 HTTP OTA固件升级路由模块
// 被 server-config.js（配置服务端口）和 server-control-tcp.js（控制服务端口）共同挂载
//
// 固件目录结构（按设备组ID建立子目录，bin文件统一命名firmware.bin）:
//   OTA/firmware/<设备组ID>/firmware.bin   待烧录固件（Arduino IDE 导出的bin）
//   OTA/firmware/<设备组ID>/version        版本号文件（纯文本，如 1.0.1）
//
// 示例（AC01空调控制器，设备组ID = keting-AC-23343313）:
//   OTA/firmware/keting-AC-23343313/firmware.bin
//   OTA/firmware/keting-AC-23343313/version
//
// 接口:
//   GET /ota/<设备组ID>/version       返回最新版本号（纯文本）
//   GET /ota/<设备组ID>/firmware.bin  下载固件文件
//
// 发布新固件流程:
//   1. Arduino IDE -> 项目 -> 导出已编译的二进制文件，得到 .bin
//   2. 复制为 OTA/firmware/<设备组ID>/firmware.bin
//   3. 递增 OTA/firmware/<设备组ID>/version 内容（如 1.0.0 -> 1.0.1）
//   4. 设备最迟在下个唤醒周期自动检查并完成升级
//
// 设备端配置示例（ESP12_IoT_AC01.ino）:
//   const char* otaVersionUrl = "http://<SERVER_IP>:<CONTROL_SERVICE_PORT>/ota/keting-AC-23343313/version";
//   const char* otaBinUrl     = "http://<SERVER_IP>:<CONTROL_SERVICE_PORT>/ota/keting-AC-23343313/firmware.bin";

const express = require('express');
const fs = require('fs');
const path = require('path');

const router = express.Router();
const FIRMWARE_ROOT = path.join(__dirname, 'firmware');

// 设备组ID只允许字母数字下划线连字符，防止路径穿越攻击
function isValidDeviceGroupId(id) {
  return /^[A-Za-z0-9_-]+$/.test(id);
}

// 版本号接口：GET /ota/:deviceGroupId/version
router.get('/ota/:deviceGroupId/version', (req, res) => {
  const { deviceGroupId } = req.params;
  if (!isValidDeviceGroupId(deviceGroupId)) {
    return res.status(400).type('text/plain').send('invalid device group id');
  }
  const versionFile = path.join(FIRMWARE_ROOT, deviceGroupId, 'version');
  fs.readFile(versionFile, 'utf8', (err, data) => {
    if (err) {
      console.log(`[OTA] ${new Date().toISOString()} GET version ${deviceGroupId} - FAILED - not found`);
      return res.status(404).type('text/plain').send('version not found');
    }
    console.log(`[OTA] ${new Date().toISOString()} GET version ${deviceGroupId} - SUCCESS - ${data.trim()}`);
    res.type('text/plain').send(data.trim());
  });
});

// 固件下载接口：GET /ota/:deviceGroupId/firmware.bin
router.get('/ota/:deviceGroupId/firmware.bin', (req, res) => {
  const { deviceGroupId } = req.params;
  console.log(`[OTA] ${new Date().toISOString()} 收到固件下载请求: ${deviceGroupId} 来自 ${req.ip}`);
  if (!isValidDeviceGroupId(deviceGroupId)) {
    return res.status(400).type('text/plain').send('invalid device group id');
  }
  const binFile = path.join(FIRMWARE_ROOT, deviceGroupId, 'firmware.bin');
  fs.stat(binFile, (err, stat) => {
    if (err) {
      console.log(`[OTA] ${new Date().toISOString()} GET firmware ${deviceGroupId} - FAILED - not found`);
      return res.status(404).type('text/plain').send('firmware not found');
    }
    console.log(`[OTA] ${new Date().toISOString()} GET firmware ${deviceGroupId} - SUCCESS - ${stat.size}字节 - 来自 ${req.ip}`);
    res.setHeader('Content-Type', 'application/octet-stream');
    res.setHeader('Content-Length', stat.size);
    fs.createReadStream(binFile).pipe(res);
  });
});

module.exports = router;
