# Security Assessment Script (Ubuntu 22.04 + Docker Compose + Laravel)

Script ini melakukan assessment bertahap sesuai praktik enterprise (OWASP/PTES/CIS baseline):

1. OS hardening check
2. Docker security check
3. Laravel security check
4. Webapp pentest check
5. Remediation config templates

## Cara pakai

```bash
chmod +x security_assessment.sh
./security_assessment.sh
```

## Contoh dengan parameter

```bash
TARGET_URL="https://example.com" \
LARAVEL_PATH="/path/to/laravel" \
COMPOSE_FILE="/path/to/docker-compose.yml" \
RUN_DOCKER_BENCH="true" \
RUN_ACTIVE_WEB_SCAN="false" \
./security_assessment.sh
```

## Output

Laporan disimpan di:

- `security_reports/assessment_<timestamp>/`
- Ringkasan: `EXEC_SUMMARY.md`
- Template perbaikan: folder `remediation/`

## Catatan

- Tool opsional (jika tersedia): `lynis`, `trivy`, `semgrep`, `nmap`, `nikto`, `nuclei`.
- Script tetap berjalan walaupun beberapa tool tidak terpasang.
- Jalankan dengan user yang punya akses Docker bila ingin scan container/image.
