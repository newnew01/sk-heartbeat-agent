# Branch Heartbeat Legacy Agent for Windows 7

Agent รุ่น Legacy สำหรับ Windows 7 SP1 และ Windows Server 2008 R2 SP1 ใช้ PowerShell Scheduled Task แทน .NET 8 Windows Service

## ข้อกำหนด

- Windows 7 SP1 หรือ Windows Server 2008 R2 SP1
- PowerShell 2.0 ขึ้นไป
- Windows Update และ Root Certificate ที่รองรับใบรับรอง HTTPS ปัจจุบัน
- TLS 1.2 ต้องใช้งานได้
- เปิด PowerShell แบบ Run as Administrator

Windows 7 หมดการสนับสนุนจาก Microsoft แล้ว ควรใช้เฉพาะเครื่อง Legacy ที่จำเป็นและจำกัดสิทธิ์ของเครื่อง

## การทำงาน

- ส่ง heartbeat ผ่าน HTTPS ทุก 1 นาที
- Task ทำงานด้วยบัญชี `SYSTEM`
- บังคับ TLS 1.2 และไม่ปิดการตรวจสอบ certificate
- Device Key เข้ารหัสด้วย Windows DPAPI แบบ `LocalMachine`
- จำกัด ACL ของ config ไว้ที่ SYSTEM และ Administrators
- ไม่เปิด inbound port
- Config และ status อยู่ใน `%ProgramData%\BranchHeartbeatLegacy`
- Scheduled Task เรียก `%ProgramData%\BranchHeartbeatLegacy\RunHeartbeat.cmd`
  เพื่อหลีกเลี่ยงปัญหาการ parse argument ของ `schtasks` บน PowerShell 2

## ติดตั้ง

แตก ZIP ไปที่ `C:\heartbeat` เปิด PowerShell แบบ Administrator แล้วรัน:

ก่อนติดตั้ง Agent ต้องมี Windows Update `KB3140245` หรืออัปเดตที่ใหม่กว่า จากนั้นเปิด TLS 1.2 และ restart เครื่อง:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\heartbeat\Enable-Tls12-Win7.ps1
shutdown /r /t 0
```

สคริปต์จะตรวจเวอร์ชัน WinHTTP ก่อนแก้ค่า registry, สำรองค่าเดิมไว้ใต้
`%ProgramData%\BranchHeartbeatLegacy\tls-registry-backup-*` และไม่ปิดการตรวจ certificate

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\heartbeat\Install-Agent-Win7.ps1 -DeviceId "DEVICE_ID_FROM_ADMIN"
```

วาง Device Key เมื่อระบบถาม

ติดตั้งแบบบรรทัดเดียวโดยใส่ Device ID และ Device Key:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\heartbeat\Install-Agent-Win7.ps1 -DeviceId "DEVICE_ID_FROM_ADMIN" -DeviceKey "DEVICE_KEY_FROM_ADMIN"
```

คำสั่งแบบ inline สะดวกสำหรับติดตั้งอัตโนมัติ แต่ Device Key จะอยู่ใน command
history และอาจมองเห็นได้จาก process command line ให้ใช้เฉพาะบนเครื่องที่ควบคุมได้
และล้างประวัติคำสั่งหลังติดตั้ง หากต้องการความปลอดภัยสูงกว่าให้ใช้โหมดถาม Key
แบบเดิม

## ตรวจสถานะ

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\BranchHeartbeatLegacy\Get-AgentStatus-Win7.ps1"
```

ตรวจ Scheduled Task:

```cmd
schtasks /Query /TN BranchHeartbeatLegacy /V /FO LIST
```

## เปลี่ยน Device ID หรือ Device Key

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\BranchHeartbeatLegacy\Configure-Agent-Win7.ps1" -DeviceId "DEVICE_ID_FROM_ADMIN"
```

## ถอนการติดตั้ง

เก็บ encrypted config ไว้:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\BranchHeartbeatLegacy\Uninstall-Agent-Win7.ps1"
```

ลบ config และ status ด้วย:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\BranchHeartbeatLegacy\Uninstall-Agent-Win7.ps1" -RemoveConfiguration
```

## แก้ปัญหา

- HTTP 401: Device ID หรือ Device Key ไม่ตรง ให้หมุน Key จาก Admin แล้ว Configure ใหม่
- TLS/secure channel error: ติดตั้ง `KB3140245` หรืออัปเดตที่ใหม่กว่า รัน `Enable-Tls12-Win7.ps1` แบบ Administrator แล้ว restart Windows
- Certificate error: อัปเดต Root Certificate ของ Windows 7 ให้ครบ ห้ามแก้โดยปิด certificate validation
- ดูผลล่าสุดจาก `Get-AgentStatus-Win7.ps1`
