#!/usr/bin/env bash
set -Eeuo pipefail

# Comprehensive security assessment for Ubuntu 22.04 + Docker Compose + Laravel
# Standards reference: OWASP ASVS, OWASP Top 10, CIS Docker Benchmark, PTES

TARGET_URL="${TARGET_URL:-http://127.0.0.1}"
LARAVEL_PATH="${LARAVEL_PATH:-$PWD}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
REPORT_ROOT="${REPORT_ROOT:-$PWD/security_reports}"
RUN_DOCKER_BENCH="${RUN_DOCKER_BENCH:-true}"
RUN_ACTIVE_WEB_SCAN="${RUN_ACTIVE_WEB_SCAN:-false}"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
REPORT_DIR="$REPORT_ROOT/assessment_$TIMESTAMP"
LOG_FILE="$REPORT_DIR/assessment.log"

mkdir -p "$REPORT_DIR" "$REPORT_DIR/remediation"

log() {
  echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"
}

run_cmd() {
  local title="$1"
  local outfile="$2"
  shift 2
  log "Running: $title"
  {
    echo "# $title"
    echo "# Command: $*"
    echo
    "$@"
  } >"$outfile" 2>&1 || true
}

section() {
  local title="$1"
  log ""
  log "========== $title =========="
}

check_tool() {
  command -v "$1" >/dev/null 2>&1
}

write_remediation_files() {
  cat >"$REPORT_DIR/remediation/01_sshd_hardening.conf" <<'EOC'
# /etc/ssh/sshd_config.d/01-hardening.conf
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
ChallengeResponseAuthentication no
X11Forwarding no
AllowTcpForwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
LoginGraceTime 30
MaxAuthTries 4
Protocol 2
EOC

  cat >"$REPORT_DIR/remediation/02_ufw_rules.sh" <<'EOC'
#!/usr/bin/env bash
set -euo pipefail
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp comment 'SSH'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw enable
sudo ufw status verbose
EOC

  cat >"$REPORT_DIR/remediation/03_docker_daemon.json" <<'EOC'
{
  "icc": false,
  "live-restore": true,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "no-new-privileges": true,
  "userns-remap": "default"
}
EOC

  cat >"$REPORT_DIR/remediation/04_laravel_env_checklist.txt" <<'EOC'
Laravel production checklist:
- APP_ENV=production
- APP_DEBUG=false
- APP_KEY set and rotated by secure procedure
- SESSION_SECURE_COOKIE=true
- SESSION_HTTP_ONLY=true
- SESSION_SAME_SITE=lax/strict
- LOG_CHANNEL=stack + centralized logging
- DB credentials in secrets manager (not committed)
- php artisan config:cache && route:cache && view:cache
- Run composer install --no-dev --optimize-autoloader
- Enforce HTTPS and secure headers in reverse proxy
EOC

  chmod +x "$REPORT_DIR/remediation/02_ufw_rules.sh"
}

stage_os_hardening() {
  section "Stage 1 - OS hardening checks"
  run_cmd "OS release" "$REPORT_DIR/os_release.txt" cat /etc/os-release
  run_cmd "Kernel & uptime" "$REPORT_DIR/os_kernel_uptime.txt" bash -lc 'uname -a; echo; uptime'
  run_cmd "Open ports" "$REPORT_DIR/os_ports_ss.txt" ss -tulpen
  run_cmd "Installed security updates (upgradable)" "$REPORT_DIR/os_upgradable.txt" bash -lc 'apt list --upgradable 2>/dev/null || true'
  run_cmd "UFW status" "$REPORT_DIR/os_ufw_status.txt" bash -lc 'ufw status verbose || true'
  run_cmd "Fail2Ban status" "$REPORT_DIR/os_fail2ban.txt" bash -lc 'systemctl status fail2ban --no-pager || true'
  run_cmd "SSH daemon config sanity" "$REPORT_DIR/os_sshd_T.txt" bash -lc 'sshd -T 2>/dev/null || true'
  run_cmd "Critical sysctl params" "$REPORT_DIR/os_sysctl_security.txt" bash -lc 'sysctl net.ipv4.ip_forward net.ipv4.conf.all.rp_filter net.ipv4.conf.default.rp_filter net.ipv4.tcp_syncookies kernel.randomize_va_space || true'

  if check_tool lynis; then
    run_cmd "Lynis quick audit" "$REPORT_DIR/os_lynis_quick.txt" lynis audit system --quick
  else
    log "lynis not installed: skipping lynis audit"
  fi
}

stage_docker_security() {
  section "Stage 2 - Docker security checks"

  if ! check_tool docker; then
    log "docker not found: skipping Docker checks"
    return
  fi

  run_cmd "Docker version" "$REPORT_DIR/docker_version.txt" docker version
  run_cmd "Docker info" "$REPORT_DIR/docker_info.txt" docker info
  run_cmd "Docker ps" "$REPORT_DIR/docker_ps.txt" docker ps -a
  run_cmd "Docker networks" "$REPORT_DIR/docker_networks.txt" docker network ls
  run_cmd "Docker volumes" "$REPORT_DIR/docker_volumes.txt" docker volume ls

  if [[ -f "$COMPOSE_FILE" ]]; then
    if check_tool docker && docker compose version >/dev/null 2>&1; then
      run_cmd "Compose config resolved" "$REPORT_DIR/docker_compose_config.txt" docker compose -f "$COMPOSE_FILE" config
    elif check_tool docker-compose; then
      run_cmd "Compose config resolved" "$REPORT_DIR/docker_compose_config.txt" docker-compose -f "$COMPOSE_FILE" config
    fi
  else
    log "Compose file not found at $COMPOSE_FILE"
  fi

  run_cmd "Container runtime security flags" "$REPORT_DIR/docker_container_security_flags.txt" bash -lc "docker inspect \
    \\$(docker ps -aq) --format '{{.Name}} user={{.Config.User}} privileged={{.HostConfig.Privileged}} readonlyRootfs={{.HostConfig.ReadonlyRootfs}} capDrop={{json .HostConfig.CapDrop}} securityOpt={{json .HostConfig.SecurityOpt}}' 2>/dev/null || true"

  if check_tool trivy; then
    run_cmd "Trivy image scan (all local images)" "$REPORT_DIR/docker_trivy_images.txt" bash -lc 'for i in $(docker images --format "{{.Repository}}:{{.Tag}}" | grep -v "<none>"); do echo "===== $i ====="; trivy image --severity HIGH,CRITICAL --quiet "$i" || true; echo; done'
  else
    log "trivy not installed: skipping image vuln scan"
  fi

  if [[ "$RUN_DOCKER_BENCH" == "true" ]]; then
    run_cmd "Docker Bench Security" "$REPORT_DIR/docker_bench_security.txt" docker run --net host --pid host --userns host --cap-add audit_control --label docker_bench_security \
      -v /etc:/etc:ro -v /usr/bin/containerd:/usr/bin/containerd:ro -v /usr/bin/runc:/usr/bin/runc:ro -v /usr/lib/systemd:/usr/lib/systemd:ro \
      -v /var/lib:/var/lib:ro -v /var/run/docker.sock:/var/run/docker.sock:ro --rm docker/docker-bench-security
  fi
}

stage_laravel_security() {
  section "Stage 3 - Laravel security checks"

  if [[ ! -d "$LARAVEL_PATH" ]]; then
    log "Laravel path not found: $LARAVEL_PATH"
    return
  fi

  run_cmd "Laravel files overview" "$REPORT_DIR/laravel_files.txt" bash -lc "cd '$LARAVEL_PATH' && pwd && ls -la"

  if [[ -f "$LARAVEL_PATH/.env" ]]; then
    run_cmd "Laravel .env key security values" "$REPORT_DIR/laravel_env_security.txt" bash -lc "cd '$LARAVEL_PATH' && awk -F= '/^(APP_ENV|APP_DEBUG|APP_KEY|APP_URL|SESSION_SECURE_COOKIE|SESSION_HTTP_ONLY|SESSION_SAME_SITE|LOG_LEVEL)=/{print \$1\"=\"\$2}' .env"
  else
    log ".env not found in $LARAVEL_PATH"
  fi

  if [[ -f "$LARAVEL_PATH/composer.json" ]]; then
    run_cmd "Composer validate" "$REPORT_DIR/laravel_composer_validate.txt" bash -lc "cd '$LARAVEL_PATH' && composer validate --no-check-publish"
    run_cmd "Composer audit" "$REPORT_DIR/laravel_composer_audit.txt" bash -lc "cd '$LARAVEL_PATH' && composer audit || true"
  fi

  if [[ -f "$LARAVEL_PATH/artisan" ]]; then
    run_cmd "Laravel optimize status" "$REPORT_DIR/laravel_artisan_about.txt" bash -lc "cd '$LARAVEL_PATH' && php artisan about || true"
    run_cmd "Laravel route list (sanity)" "$REPORT_DIR/laravel_routes.txt" bash -lc "cd '$LARAVEL_PATH' && php artisan route:list --except-vendor || true"
  fi

  run_cmd "Laravel sensitive file permissions" "$REPORT_DIR/laravel_permissions.txt" bash -lc "cd '$LARAVEL_PATH' && find . -maxdepth 3 -type f \( -name '.env' -o -name '*.key' -o -name '*.pem' \) -exec ls -l {} \;"

  if check_tool semgrep; then
    run_cmd "Semgrep Laravel security rules" "$REPORT_DIR/laravel_semgrep.txt" semgrep --config p/laravel "$LARAVEL_PATH"
  else
    log "semgrep not installed: skipping SAST"
  fi
}

stage_webapp_pentest() {
  section "Stage 4 - Webapp pentest checks"
  run_cmd "Basic HTTP headers" "$REPORT_DIR/web_headers_curl.txt" bash -lc "curl -k -I '$TARGET_URL'"

  if check_tool nmap; then
    run_cmd "Nmap service scan (top ports)" "$REPORT_DIR/web_nmap.txt" bash -lc "nmap -sV --top-ports 100 \"\$(echo '$TARGET_URL' | sed -E 's#https?://##; s#/.*##')\""
  else
    log "nmap not installed: skipping nmap"
  fi

  if check_tool nikto; then
    run_cmd "Nikto web vulnerability scan" "$REPORT_DIR/web_nikto.txt" nikto -h "$TARGET_URL"
  else
    log "nikto not installed: skipping nikto"
  fi

  if check_tool nuclei; then
    run_cmd "Nuclei OWASP top10 templates" "$REPORT_DIR/web_nuclei.txt" nuclei -u "$TARGET_URL" -tags owasp,misconfig,cve
  else
    log "nuclei not installed: skipping nuclei"
  fi

  if [[ "$RUN_ACTIVE_WEB_SCAN" == "true" ]]; then
    if check_tool docker; then
      run_cmd "OWASP ZAP baseline scan" "$REPORT_DIR/web_zap_baseline.txt" docker run --rm -t owasp/zap2docker-stable zap-baseline.py -t "$TARGET_URL" -r zap_report.html
    else
      log "docker unavailable: skipping ZAP baseline"
    fi
  fi
}

stage_summary() {
  section "Stage 5 - Remediation configs & summary"
  write_remediation_files

  cat >"$REPORT_DIR/EXEC_SUMMARY.md" <<EOS
# Security Assessment Executive Summary

- Timestamp: $TIMESTAMP
- Target URL: $TARGET_URL
- Laravel Path: $LARAVEL_PATH
- Compose File: $COMPOSE_FILE

## Completed stages
1. OS hardening checks (Ubuntu baseline, network exposure, SSH/UFW/sysctl, optional Lynis)
2. Docker security checks (daemon/runtime/container settings, compose config, optional Trivy + Docker Bench)
3. Laravel security checks (.env posture, dependency audit, artisan surface, permissions, optional Semgrep)
4. Web application pentest checks (headers, nmap, Nikto, optional Nuclei/ZAP)
5. Remediation templates generated under ./remediation

## Next actions (enterprise workflow)
1. Prioritize CRITICAL/HIGH findings from Trivy/Composer/Nuclei/Nikto.
2. Create risk register with CVSS + exploitability + business impact.
3. Patch and harden in staging first, then re-scan.
4. Add this script to CI/CD and run routinely (weekly + pre-release).
EOS

  log "Assessment completed. Reports at: $REPORT_DIR"
  log "Start reading: $REPORT_DIR/EXEC_SUMMARY.md"
}

main() {
  section "Security Assessment started"
  log "Report directory: $REPORT_DIR"
  stage_os_hardening
  stage_docker_security
  stage_laravel_security
  stage_webapp_pentest
  stage_summary
}

main "$@"
