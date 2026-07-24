# Windows Branch Heartbeat Agent

Windows Service สำหรับ Windows 10/11 x64 ที่ต่ออายุ Public IPv4 ของสาขาใน
MSSQL allowlist

## ติดตั้ง

แตก ZIP ไปที่ `C:\heartbeat` แล้วเปิด PowerShell แบบ Run as Administrator

โหมดปลอดภัยกว่า โดยระบบจะถาม Device Key:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\heartbeat\Install-Agent.ps1 -DeviceId "DEVICE_ID_FROM_ADMIN"
```

โหมดบรรทัดเดียว:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\heartbeat\Install-Agent.ps1 -DeviceId "DEVICE_ID_FROM_ADMIN" -DeviceKey "DEVICE_KEY_FROM_ADMIN"
```

คำเตือน: โหมดบรรทัดเดียวทำให้ Device Key อยู่ใน command history และอาจมองเห็น
จาก process command line

## ตรวจสถานะ

```powershell
C:\heartbeat\Get-AgentStatus.ps1
Get-Service BranchHeartbeatAgent
```

## เปลี่ยน Device ID หรือ Device Key

```powershell
C:\heartbeat\Configure-Agent.ps1 -DeviceId "DEVICE_ID_FROM_ADMIN"
```

หรือแบบบรรทัดเดียว:

```powershell
C:\heartbeat\Configure-Agent.ps1 -DeviceId "DEVICE_ID_FROM_ADMIN" -DeviceKey "DEVICE_KEY_FROM_ADMIN"
```

## ถอนการติดตั้ง

เก็บ encrypted config:

```powershell
C:\heartbeat\Uninstall-Agent.ps1
```

ลบ config และ encrypted Device Key:

```powershell
C:\heartbeat\Uninstall-Agent.ps1 -RemoveConfiguration
```

Agent ส่ง heartbeat ทันทีเมื่อ service เริ่ม จากนั้นทุก 60 วินาที และ retry
ทุก 15 วินาทีเมื่อส่งไม่สำเร็จ Device Key ถูกเข้ารหัสด้วย Windows DPAPI
แบบ `LocalMachine` และ Agent ไม่เปิด inbound port
