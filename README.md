# Security Assessment + Web Dashboard (React + Node.js + PostgreSQL)

Ini paket lengkap yang bisa langsung dijalankan untuk:

1. Menjalankan **security assessment** multi-stage (OS, Docker, Laravel, web pentest, remediation).
2. Menyimpan hasil assessment ke **PostgreSQL**.
3. Menampilkan hasil assessment terbaru di **dashboard React.js**.

## Arsitektur

- `security_assessment.sh` → scanner utama
- `api/` (Node.js + Express) → REST API + importer hasil scan
- `web/` (React + Vite + Nginx) → dashboard UI
- `postgres` → database hasil assessment
- `docker-compose.yml` → orkestrasi semuanya

## Jalankan sekali command (recommended)

```bash
chmod +x security_assessment.sh scripts/run_full_stack.sh
./scripts/run_full_stack.sh
```

Setelah selesai:
- Dashboard: http://localhost:3000
- API latest assessment: http://localhost:8080/api/assessments/latest

## Jalankan manual per tahap

```bash
# 1) start stack
docker compose up -d --build

# 2) run assessment + import ke API
API_IMPORT_URL="http://localhost:8080/api/assessments/import" \
TARGET_URL="http://127.0.0.1" \
LARAVEL_PATH="/path/laravel" \
./security_assessment.sh
```

## Variable penting

- `TARGET_URL` target aplikasi web
- `LARAVEL_PATH` path source Laravel
- `COMPOSE_FILE` lokasi compose file aplikasi Anda
- `RUN_DOCKER_BENCH` (`true/false`)
- `RUN_ACTIVE_WEB_SCAN` (`true/false`)
- `API_IMPORT_URL` endpoint import hasil assessment ke dashboard

## Catatan

- Tool opsional (auto-detect): `lynis`, `trivy`, `semgrep`, `nmap`, `nikto`, `nuclei`.
- Jika tool tidak ada, check akan di-skip dan dicatat di log.
- Report mentah tetap disimpan di `security_reports/assessment_<timestamp>/`.
