# Session Handoff — Branch Heartbeat

อัปเดตล่าสุด: 2026-07-25 (Asia/Bangkok)

เอกสารนี้ใช้ส่งต่องานให้ session ถัดไป โปรดตรวจสถานะจริงอีกครั้งก่อนเปลี่ยน firewall หรือ production service และห้าม commit รหัสผ่าน, Device Key หรือ private key ลง repository

## เป้าหมายของระบบ

อนุญาตให้ร้านสาขาที่มี Dynamic Public IPv4 เชื่อมต่อ MSSQL บน VPS พอร์ต TCP 1444 โดยไม่ใช้ VPN:

1. Windows Agent ของสาขาส่ง HTTPS heartbeat
2. Server อ่าน Public IPv4 จากการเชื่อมต่อจริง
3. Server เพิ่ม/ต่ออายุ IP ใน `ipset`
4. UFW อนุญาต TCP 1444 เฉพาะ IP ที่ยังมี lease อยู่
5. หากไม่มี heartbeat ประมาณ 600 วินาที IP จะหมดอายุและถูกนำออกอัตโนมัติ

ข้อจำกัดที่ผู้ใช้ยอมรับแล้ว: หากสาขาอยู่หลัง CGNAT การอนุญาตจะครอบคลุม Public IPv4 ที่แชร์กับผู้ใช้อื่นของ ISP ด้วย แต่ยังดีกว่าเปิดพอร์ตให้ทั้งอินเทอร์เน็ต

## Production VPS

- OS: Ubuntu 22.04 พร้อม aaPanel
- Host/IP: `157.85.103.205`
- SSH user: `root`
- Private key อยู่ที่เครื่อง operator: `D:\sk-server.ppk` (ห้าม commit ไฟล์นี้)
- Public URL: `https://heartbeat.184184184.xyz`
- Heartbeat endpoint: `POST /api/v1/heartbeat`
- App directory: `/opt/branch-heartbeat`
- Environment file: `/etc/branch-heartbeat/heartbeat.env`
- SQLite database: `/var/lib/branch-heartbeat/heartbeat.db`
- Initial admin credential file: `/root/branch-heartbeat-initial-admin.txt` permission `600`
- systemd app unit: `branch-heartbeat.service`
- App ฟังเฉพาะ `127.0.0.1:8787`
- aaPanel Nginx reverse proxy extension:
  `/www/server/panel/vhost/nginx/extension/heartbeat.184184184.xyz/branch-heartbeat.conf`

ห้ามพิมพ์ credential หรือ Device Key ลง log/chat ให้ผู้ใช้เปิดไฟล์ credential บน VPS ด้วยตนเองเมื่อจำเป็น

## Firewall และ ipset

- UFW active, default incoming `deny`
- `iptables v1.8.7 (nf_tables)`
- Dynamic set: `branch_sql_allow_v4`
- Set type: `hash:ip family inet timeout 600 comment`
- Persistence unit: `/etc/systemd/system/branch-sql-ipset.service`
- Unit enabled และสร้าง set ก่อน UFW
- Persistent allow rule อยู่ใน `/etc/ufw/before.rules` ก่อน `COMMIT`:

```text
-A ufw-before-input -p tcp --dport 1444 -m set --match-set branch_sql_allow_v4 src -m comment --comment "branch-sql-heartbeat" -j ACCEPT
```

aaPanel UI อาจไม่แสดง custom rule นี้ เพราะไม่ได้สร้างผ่าน aaPanel firewall UI

คำสั่งตรวจสอบ:

```bash
systemctl is-active branch-sql-ipset.service
systemctl is-active branch-heartbeat.service
ipset list branch_sql_allow_v4
iptables -S ufw-before-input | grep branch-sql
ufw status numbered
journalctl -u branch-heartbeat.service --since "10 minutes ago" --no-pager
```

## สถานะล่าสุดที่ยืนยันแล้ว

- หน้า Admin แสดงสถานะต่ออุปกรณ์แล้ว: จุดเขียว `ออนไลน์` เมื่อ branch/device เปิดใช้งานและ lease ยังไม่หมดอายุ; จุดเทา `ออฟไลน์` เมื่อหมดอายุ, ถูกปิด หรือยังไม่เคย heartbeat
- ฟีเจอร์สถานะ deploy ขึ้น production แล้วจาก commit `0fc27de`
- Backup ก่อน deploy: `/opt/branch-heartbeat-backups/0fc27de-predeploy-20260724-162637.tar.gz`
- หน้า Admin แปลงเวลา UTC เป็นเวลาไทย GMT+7 รูปแบบ `DD/MM/YYYY HH:MM:SS` แล้วจาก commit `9f6823f`
- Backup ก่อน deploy timezone: `/opt/branch-heartbeat-backups/9f6823f-predeploy-20260724-163043.tar.gz`
- Windows Agent เครื่องทดสอบติดตั้งเป็น service และขึ้น `healthy`
- Service name: `BranchHeartbeatAgent`
- Branch code: `006`
- Branch name: `เอส.เค.บ้านโฮ่ง`
- Device code: `new-laptop`
- Device ID (ไม่ใช่ secret): `hM4bH-PN8TNa7HGgiqYLonyo`
- Public IPv4 ล่าสุด: `1.20.222.85`
- `ipset` comment: `006-new-laptop`
- Agent heartbeat ทุก 60 วินาที
- Retry เมื่อผิดพลาดทุก 15 วินาที
- Server lease/ipset timeout: 600 วินาที

ค่าข้างต้นเปลี่ยนได้ โดยเฉพาะ Public IP และ timeout ต้องตรวจจากระบบจริงเสมอ

## Incident (2026-07-25): Heartbeat loop ค้างเงียบบน Windows Agent

อาการ: `BranchHeartbeat.Agent.exe status` ค้าง `state: error` เวลาเดิมซ้ำ ๆ
ไม่ขยับเลยแม้รอหลายนาที ทั้งที่ `Get-Service BranchHeartbeatAgent` ยัง
`Running` ผู้ใช้แจ้งว่าเกิดกับหลายเครื่องพร้อมกัน

ตรวจสอบฝั่ง VPS (SSH เข้า `root@157.85.103.205` ด้วยคีย์ที่แปลงจาก
`.ppk` เป็น OpenSSH `.pem` — puttygen บนเครื่อง Windows ของผู้ใช้ เพราะ
เครื่อง dev เป็น Linux Mint ไม่มี `puttygen`/`plink` และไม่มี sudo
ติดตั้งเพิ่มได้) พบว่า `branch-heartbeat.service` และ nginx (aaPanel,
path จริงคือ `/www/server/nginx`, log อยู่ที่
`/www/wwwlogs/heartbeat.184184184.xyz.log`) ทำงานปกติตลอด ไม่มี error,
ไม่มี restart Access log แสดงว่า agent เครื่องที่มีปัญหาส่ง heartbeat
สำเร็จทุก 60 วินาทีตรงเวลา จนถึงนาทีหนึ่งแล้ว**หยุดส่ง request ออกจาก
เครื่องไปเลย** (ไม่ใช่แค่ error/timeout) สรุปว่าปัญหาอยู่ฝั่ง client
ล้วน ๆ ไม่ใช่ server

Root cause (ยืนยันโดยตรวจโค้ด `HeartbeatWorker.ExecuteAsync`):
`ConfigurationStore.Load()` และโดยเฉพาะ `UnprotectDeviceKey()`
(`ProtectedData.Unprotect` / DPAPI) เป็น synchronous call ที่**ไม่มี
timeout ใด ๆ** ถ้า DPAPI/LSASS ค้าง (เช่น AV/EDR hook เข้าไปตรวจ
Crypt API) เธรดจะค้างตลอดกาลโดยไม่ throw จึงไม่มีทาง reach catch block
เดิมที่จะ log/เขียน status ใหม่ได้เลย — อธิบาย symptom ได้ตรงเป๊ะ
(ดู `client/scripts/Install-Agent.ps1:95-96` ที่ตั้ง
`sc.exe failure ... actions= restart/...` และ `failureflag 1` ไว้แล้ว
แต่ไม่เคย trigger เพราะ process ไม่เคย "ตาย" มันแค่ค้าง)

แก้ไขแล้วใน commit `ff6c1e0`:

- `client/BranchHeartbeat.Agent/HeartbeatWorker.cs` — ครอบ `Load()`/
  `UnprotectDeviceKey()` ด้วย `RunWithTimeoutAsync` (timeout 20 วินาที)
  ถ้าเกินจะ throw `TimeoutException` เข้า catch block เดิมตามปกติ
- `client/BranchHeartbeat.Agent/HeartbeatWatchdog.cs` (ไฟล์ใหม่) —
  `BackgroundService` ที่สองคอยเช็คทุก 30 วินาทีว่า `status.json`
  (`UpdatedAt`) เก่าเกิน 5 นาทีไหม (grace period 2 นาทีตอน startup)
  ถ้าค้างจริงจะ `Environment.Exit(1)` ให้ SCM auto-restart ตาม
  recovery action ที่ตั้งไว้แล้ว ครอบคลุม hang กรณีอื่นในอนาคตด้วย
  ไม่ใช่แค่ DPAPI
- ลงทะเบียนใน `Program.cs`: `AddHostedService<HeartbeatWatchdog>()`

ตรวจสอบแล้วบน Linux Mint (เครื่อง dev): `dotnet build` ผ่าน 0 warning/
error (ใช้ `EnableWindowsTargeting=true` compile ข้าม platform ได้)
รัน `dotnet run` ใน `BranchHeartbeat.Agent.Tests` ผ่าน 2/3 เทส
(`heartbeat request`, `status round-trip`) ส่วน
`configuration round-trip` fail เพราะ DPAPI รันบน Linux ไม่ได้ (ข้อจำกัด
แพลตฟอร์ม ไม่เกี่ยวกับโค้ดที่แก้) **ยังไม่ได้ทดสอบ watchdog แบบ
end-to-end บน Windows จริง** (จำลอง hang แล้วดูว่า service restart
จริงไหม)

งานที่เหลือ:

1. Build release ใหม่บน Windows ด้วย
   `client/Build-Release.ps1` (bump version, เช่น `1.0.2`)
2. ทดสอบ watchdog บนเครื่อง Windows จริง (เช่นหยุด thread จำลอง hang
   หรือรอดูพฤติกรรมจริงในโปรดักชัน)
3. Deploy ไปทุกเครื่องที่เคยเจออาการ `state: error` ค้าง โดยเฉพาะ
   เครื่อง branch `006` (`new-laptop`, device ID `hM4bH-PN8TNa7HGgiqYLonyo`)
4. พิจารณาทำแบบเดียวกันกับ Windows 7 Legacy Agent
   (`client/legacy-win7`) หากใช้ DPAPI แบบ synchronous เหมือนกัน —
   ยังไม่ได้ตรวจโค้ดฝั่งนั้นในรอบนี้

## งานสำคัญที่ยังค้าง

กฎ UFW สาธารณะเดิมยังเปิดอยู่:

```text
1444/tcp      ALLOW IN Anywhere
1444/tcp (v6) ALLOW IN Anywhere (v6)
```

ยังไม่ได้ลบเพราะรอผู้ใช้อนุมัติขั้นตอนสุดท้าย แม้ Agent จะ healthy แล้วก็ตาม

ก่อนลบ:

1. ตรวจว่า `branch_sql_allow_v4` มี IP และ timeout กำลังต่ออายุ
2. ขอคำยืนยันจากผู้ใช้ก่อนเปลี่ยน production firewall
3. เก็บ SSH session เปิดไว้
4. ลบเฉพาะกฎ `allow 1444/tcp` สาธารณะ ห้ามลบ custom ipset rule
5. ทดสอบ MSSQL จากเครื่อง Agent และทดสอบจาก IP ที่ไม่ได้รับอนุญาต

ตัวอย่างคำสั่งหลังได้รับอนุมัติ:

```bash
ufw status numbered
ufw --force delete allow 1444/tcp
ufw status verbose
iptables -S ufw-before-input | grep branch-sql
ipset list branch_sql_allow_v4
```

ตรวจหมายเลข rule ใหม่ทุกครั้งหากเลือกใช้ `ufw delete <number>` เพราะหมายเลขเปลี่ยนได้

## Windows Agent

- Source: `client/BranchHeartbeat.Agent`
- Tests: `client/BranchHeartbeat.Agent.Tests`
- Installer scripts: `client/scripts`
- Latest GitHub Release: `https://github.com/newnew01/sk-heartbeat-agent/releases/tag/v1.0.2`
- Modern Windows ZIP SHA-256: `4B9F07DC28A5BAE784C5C94E6E6E466B7D8B84E57FA62A00999794938785E45B`
- `v1.0.2` เพิ่ม timeout ให้ DPAPI config load และ watchdog สำหรับ restart
  Windows Service อัตโนมัติเมื่อ heartbeat loop ค้าง
- `v1.0.1` เพิ่ม optional `-DeviceKey` สำหรับติดตั้งบรรทัดเดียวบน Windows 10/11
  แต่ plaintext Key จะอยู่ใน command history/process command line
- Release ZIP ถูกเก็บเป็น GitHub Release asset ไม่ได้เก็บซ้ำใน branch
- Agent เป็น .NET 8 self-contained single-file สำหรับ Windows x64
- ไม่ต้องติดตั้ง .NET runtime เพิ่ม
- Device Key เข้ารหัสด้วย Windows DPAPI แบบ `LocalMachine`
- Config/status อยู่ใต้ `%ProgramData%\BranchHeartbeat`
- ACL จำกัดไว้ที่ `SYSTEM` และ `Administrators`
- Agent ไม่เปิด inbound port
- Binary ยังไม่ได้ code-sign จึงอาจมี Windows SmartScreen warning

### Windows 7 Legacy Agent

- Source: `client/legacy-win7`
- Tests: `client/Test-Win7-Agent.ps1`
- Build: `client/Build-Win7-Release.ps1`
- Latest release tag: `win7-v1.0.6`
- Release SHA-256: `979F57B903F1D6928BD5D26B521673B1147BA902397EFE56F17C2CEA06E60880`
- `win7-v1.0.1` เพิ่ม optional `-DeviceKey` สำหรับติดตั้งบรรทัดเดียว
  แต่ plaintext Key จะอยู่ใน command history/process command line
- `win7-v1.0.2` แก้ PowerShell 2/.NET รุ่นเก่าที่ `SHA256Managed.Dispose()`
  ใช้งานไม่ได้ โดยเปลี่ยนเป็น `Clear()` และห้าม runtime scripts ใช้ `.Dispose()`
- `win7-v1.0.3` แก้ `schtasks` บน PowerShell 2 แยก `-NoProfile` เป็น option
  โดยสร้าง `%ProgramData%\BranchHeartbeatLegacy\RunHeartbeat.cmd` และส่ง
  path ที่ไม่มี argument ให้ `/TR`
- `win7-v1.0.4` เปลี่ยน heartbeat transport เป็น WinHTTP, เพิ่ม TLS preflight และ
  `Enable-Tls12-Win7.ps1` สำหรับตรวจ KB3140245/อัปเดตที่ใหม่กว่า สำรอง registry
  และเปิด TLS 1.2 โดยยังตรวจ certificate ตามปกติ
- `win7-v1.0.5` แก้การอ่านเวอร์ชัน `winhttp.dll` บน Windows 7 ซึ่งค่า `FileVersion`
  อาจมีข้อความ build ต่อท้าย โดยอ่านส่วนตัวเลขจาก `FileVersionInfo` โดยตรง
- `win7-v1.0.6` รองรับ registry key และ Scheduled Task ที่ยังไม่มีบน PowerShell 2,
  ตรวจ read-back ค่า TLS หลังเขียน และสร้าง registry backup path ที่ไม่ซ้ำกัน
- รองรับ Windows 7 SP1 และ Windows Server 2008 R2 SP1
- ใช้ PowerShell 2-compatible script และ Scheduled Task `BranchHeartbeatLegacy`
- Scheduled Task รันทุก 1 นาทีด้วยบัญชี `SYSTEM`
- บังคับ TLS 1.2 โดยไม่ปิด certificate validation
- Device Key เข้ารหัสด้วย DPAPI `LocalMachine`
- Config/status: `%ProgramData%\BranchHeartbeatLegacy`
- Production API smoke test ผ่านแล้ว และลบ branch/device/audit ทดสอบแล้ว
- ยังไม่ได้ทดสอบบนเครื่อง Windows 7 จริง; ผ่าน static PowerShell 2 compatibility scan,
  DPAPI round-trip และ production API smoke test บน Windows รุ่นปัจจุบัน

ติดตั้ง:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Install-Agent.ps1 -DeviceId 'DEVICE_ID_FROM_ADMIN'
```

เปลี่ยน Device ID/Key โดยไม่ติดตั้งใหม่:

```powershell
.\Configure-Agent.ps1 -DeviceId 'DEVICE_ID_FROM_ADMIN'
```

ตรวจสถานะ:

```powershell
.\Get-AgentStatus.ps1
Get-Service BranchHeartbeatAgent
```

หากได้ HTTP 401 ให้ตรวจว่าใช้ `Device ID` (UID ที่ระบบสร้าง) ไม่ใช่ Device code/name และหมุน Device Key ใหม่จาก Admin UI

เครื่องหลายเครื่องที่ออกอินเทอร์เน็ตผ่าน router/Public IP เดียวกัน ใช้ Agent เพียงหนึ่งเครื่องที่เปิดตลอดก็พอ หากอยู่คนละ WAN/Public IP ต้องมี Agent อย่างน้อยหนึ่งตัวต่อเครือข่าย

## API Authentication

Agent ส่ง:

```http
POST /api/v1/heartbeat
Authorization: Bearer DEVICE_KEY
X-Device-ID: DEVICE_ID
```

Server เก็บเฉพาะ SHA-256 ของ Device Key และแสดง plaintext key เพียงครั้งเดียวตอนสร้างหรือหมุน Key

## Repository และการทดสอบ

- GitHub: `https://github.com/newnew01/sk-heartbeat-agent.git`
- Branch: `main`
- Agent release commit ก่อนเอกสารนี้: `c598166`
- Admin device-status commit: `0fc27de`

ทดสอบ server:

```powershell
python -m pytest -q
```

ทดสอบ Agent:

```powershell
dotnet run --project .\client\BranchHeartbeat.Agent.Tests\BranchHeartbeat.Agent.Tests.csproj -c Release
```

Build release:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\client\Build-Release.ps1 -Version 1.0.0
```

Production Agent smoke test เคยผ่านแล้ว โดย Agent ส่ง heartbeat จริง, IP เข้า `ipset` และข้อมูลทดสอบถูก cleanup หลังทดสอบ

## ข้อควรระวัง

- aaPanel มี chains/ipsets ของตัวเอง อย่าแก้หรือลบ rule ที่ไม่เกี่ยวข้อง
- `aapanel.ipv4.whitelist` ถูก ACCEPT ก่อน UFW; อย่าเพิ่ม IP สาขาเข้า global aaPanel whitelist เพราะจะเปิดทุก service ไม่ใช่เฉพาะ MSSQL
- อย่าเปลี่ยน timeout ให้สั้นกว่า heartbeat/retry จน lease หลุดง่าย
- การเปิด MSSQL ด้วย IP allowlist ไม่ทดแทนรหัสผ่านที่แข็งแรง, TLS และการจำกัดสิทธิ์ SQL login
- อย่าลบ `branch_sql_allow_v4` ขณะ UFW rule ยังอ้างอิง set อยู่
- อย่า commit โฟลเดอร์ config จาก `%ProgramData%`, SQLite production DB, admin credential, Device Key หรือ SSH private key
