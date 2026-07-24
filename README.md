# Branch Heartbeat

ระบบอนุญาต Public IPv4 ของสาขาเข้า MSSQL ผ่าน heartbeat lease พร้อมหน้า Admin สำหรับจัดการสาขาและ Device Key

Windows Agent และสคริปต์ติดตั้งอยู่ใน [`client/`](client/README.md)

## คุณสมบัติ

- Admin login และ CSRF protection
- สร้าง/ปิดสาขาและอุปกรณ์
- Device Key แสดงเพียงครั้งเดียวและเก็บเฉพาะ SHA-256
- Heartbeat API อัปเดต `ipset` พร้อม timeout
- SQLite audit log
- รันแบบ dedicated system user และจำกัด capability เหลือ `CAP_NET_ADMIN`
- ฟังเฉพาะ `127.0.0.1:8787` หลัง Nginx

## Endpoint

```http
POST /api/v1/heartbeat
Authorization: Bearer DEVICE_KEY
X-Device-ID: DEVICE_ID
```

Nginx ต้องส่ง `X-Real-IP $remote_addr` และ hostname ควรเป็น DNS-only เพื่อให้เห็น IP ของสาขาจริง

## การติดตั้งโดยสรุป

1. แตกไฟล์ไปที่ `/opt/branch-heartbeat`
2. สร้าง virtual environment และติดตั้ง `requirements.txt`
3. สร้าง `/var/lib/branch-heartbeat` ให้ user `branch-heartbeat` เขียนได้
4. สร้าง `/etc/branch-heartbeat/heartbeat.env` จากตัวอย่างและกำหนด permission `640`
5. ติดตั้ง systemd unit จาก `deploy/branch-heartbeat.service`
6. สร้างฐานข้อมูลและ admin แรกด้วย Flask CLI
7. เปิด service และตั้ง Nginx reverse proxy

คำสั่งติดตั้งแบบละเอียดจะดำเนินการทีละขั้นหลังอัปโหลดแพ็กเกจขึ้น VPS

สำหรับการติดตั้งอัตโนมัติ สามารถสร้างไฟล์รหัสผ่านที่ permission ปลอดภัยแล้วใช้:

```bash
flask --app wsgi create-admin --username admin --password-file /path/to/password
```
