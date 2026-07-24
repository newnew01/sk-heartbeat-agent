# Session Handoff — Branch Heartbeat

อัปเดตล่าสุด: 2026-07-24 (Asia/Bangkok)

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
- GitHub Release: `https://github.com/newnew01/sk-heartbeat-agent/releases/tag/v1.0.0`
- Release ZIP ถูกเก็บเป็น GitHub Release asset ไม่ได้เก็บซ้ำใน branch
- SHA-256:
  `1002998AD6E9913A057854E2A6BB38C2471B4AEC3FA4939C44B22023C2142882`
- Agent เป็น .NET 8 self-contained single-file สำหรับ Windows x64
- ไม่ต้องติดตั้ง .NET runtime เพิ่ม
- Device Key เข้ารหัสด้วย Windows DPAPI แบบ `LocalMachine`
- Config/status อยู่ใต้ `%ProgramData%\BranchHeartbeat`
- ACL จำกัดไว้ที่ `SYSTEM` และ `Administrators`
- Agent ไม่เปิด inbound port
- Binary ยังไม่ได้ code-sign จึงอาจมี Windows SmartScreen warning

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
