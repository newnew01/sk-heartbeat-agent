# Windows Branch Heartbeat Agent

Windows Service ที่ต่ออายุ Public IPv4 ของสาขาสำหรับ MSSQL allowlist

## ดาวน์โหลด

- [GitHub Release v1.0.0](https://github.com/newnew01/sk-heartbeat-agent/releases/tag/v1.0.0)
- [ดาวน์โหลด BranchHeartbeat-Agent-1.0.0-win-x64.zip](https://github.com/newnew01/sk-heartbeat-agent/releases/download/v1.0.0/BranchHeartbeat-Agent-1.0.0-win-x64.zip)
- SHA-256: `1002998AD6E9913A057854E2A6BB38C2471B4AEC3FA4939C44B22023C2142882`

แพ็กเกจเป็น self-contained สำหรับ Windows x64 จึงไม่ต้องติดตั้ง .NET เพิ่ม หาก Windows แสดงคำเตือนเพราะไฟล์ยังไม่ได้ code-sign ให้ตรวจสอบ SHA-256 ก่อนติดตั้ง

## Windows 7 SP1

Agent `v1.0.0` ด้านบนใช้ .NET 8 และไม่รองรับ Windows 7 สำหรับเครื่อง Legacy
ให้ใช้แพ็กเกจ PowerShell Scheduled Task แยก:

- [คู่มือ Windows 7 Legacy Agent](legacy-win7/README.md)
- [GitHub Release win7-v1.0.0](https://github.com/newnew01/sk-heartbeat-agent/releases/tag/win7-v1.0.0)
- SHA-256: `DD00676DD10742E0856CB2BD5692E0B6C99C9C68CBE986050517A65DD184D07E`

Legacy Agent ส่ง heartbeat ทุก 1 นาทีด้วยบัญชี SYSTEM, ใช้ TLS 1.2 และเข้ารหัส
Device Key ด้วย Windows DPAPI โดยไม่ต้องเปลี่ยน Heartbeat API ฝั่ง VPS

## พฤติกรรม

- ส่ง heartbeat ทันทีเมื่อ service เริ่ม
- ส่งปกติทุก 60 วินาที
- retry ทุก 15 วินาทีเมื่อเกิดข้อผิดพลาด
- HTTP timeout 15 วินาที
- เก็บ Device Key ด้วย Windows DPAPI (`LocalMachine`)
- จำกัด ACL ของ config ให้เฉพาะ `SYSTEM` และ `Administrators`
- เขียนสถานะล่าสุดที่ `%ProgramData%\BranchHeartbeat\status.json`
- ไม่เปิด inbound port

## ติดตั้ง

1. สร้างสาขาและอุปกรณ์จากหน้า Admin
2. แตกไฟล์ release ZIP บนเครื่องสาขา
3. เปิด PowerShell แบบ **Run as Administrator**
4. รัน:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Install-Agent.ps1 -DeviceId 'DEVICE_ID_FROM_ADMIN'
```

5. Paste Device Key เมื่อระบบถาม โดย Key จะไม่ปรากฏใน command line

## ตรวจสถานะ

```powershell
.\Get-AgentStatus.ps1
Get-Service BranchHeartbeatAgent
```

## เปลี่ยน Device Key

```powershell
.\Configure-Agent.ps1 -DeviceId 'DEVICE_ID_FROM_ADMIN'
```

## ถอนการติดตั้ง

เก็บ config ไว้:

```powershell
.\Uninstall-Agent.ps1
```

ลบ config และ encrypted key:

```powershell
.\Uninstall-Agent.ps1 -RemoveConfiguration
```
