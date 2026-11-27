#!/usr/bin/env bash
# policy_audit.sh - check the kente-app server against Server Configuration
# Policy v2.1 and print PASS / FAIL / WARN for every item.
#
# READ-ONLY: this script never changes the server. The only side effect is one
# GET /health request, which adds one line to access.log like any other request.
#
# Usage:   sudo scripts/policy_audit.sh
#          sudo scripts/policy_audit.sh | tee ~/audit/policy-$(date +%F).txt
# Exit:    0 = no FAIL, 1 = at least one FAIL, 2 = not run as root
#
# Why this exists: the 12-26 Nov 2026 outage (inventory hostname pointed at the
# wrong IP) went unnoticed for 15 days because nothing checked the server
# against the policy. This makes "correct" a command anyone can run.
#
# To change what "correct" means, edit the settings below in a reviewed PR.
set -uo pipefail

# ---------- settings (keep in step with the policy document) ----------
EXPECTED_HOSTNAME="kente-app-01"
SERVICE_USER="kentesvc"
OPS_GROUP="kente-ops"
CURRENT_ENGINEERS="engineer"          # space-separated
ASSESSOR="instructor"                 # policy 2.4: must stay exactly as found
ASSESSOR_UID="1000"                   # baseline recorded in the 2026-11-27 audit
ASSESSOR_SHELL="/bin/bash"
ASSESSOR_GROUPS="instructor"
FORMER_STAFF="ydarko"                 # space-separated
ALLOWED_PUBLIC_TCP_PORTS="22 8080"    # policy 5.1
ALLOWED_UFW_RULES="22/tcp 8080/tcp"
INVENTORY_HOST="inventory.kente.internal"
HEALTH_URL="http://localhost:8080/health"
APP_LOG="/var/log/kente-app/access.log"
# path  owner:group  mode   (policy section 3)
PATH_RULES="
3.1 /opt/kente-app                 root:kente-ops     755
3.2 /opt/kente-app/data            kentesvc:kente-ops 750
3.3 /opt/kente-app/config/app.conf root:kente-ops     640
3.4 /var/log/kente-app             kentesvc:kente-ops 750
3.5 /backups                       root:root          700
"
# ----------------------------------------------------------------------

PASS=0; FAIL=0; WARN=0
pass() { printf 'PASS  %-5s %s\n' "$1" "$2"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL  %-5s %s\n' "$1" "$2"; FAIL=$((FAIL + 1)); }
warn() { printf 'WARN  %-5s %s\n' "$1" "$2"; WARN=$((WARN + 1)); }
section() { printf '\n== %s\n' "$1"; }
# check_eq ID DESCRIPTION EXPECTED ACTUAL
check_eq() {
  if [ "$4" = "$3" ]; then pass "$1" "$2: $4"
  else fail "$1" "$2: expected '$3', got '${4:-<nothing>}'"; fi
}
in_list() { case " $2 " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
has_sudo() { sudo -l -U "$1" 2>/dev/null | grep -q 'may run the following'; }
words_sorted() { tr ' ,' '\n\n' | sed '/^$/d' | sort -u | tr '\n' ' ' | sed 's/ $//'; }

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  sed -n '2,13p' "$0"; exit 0
fi
if [ "$(id -u)" -ne 0 ]; then
  echo "Run with sudo: it needs root to read sudo rules, shadow status and ufw." >&2
  exit 2
fi

echo "kente-app policy audit (policy v2.1) - $(date '+%Y-%m-%d %H:%M:%S %Z') on $(hostname)"
echo "Read-only. Every FAIL is a difference from the policy; fix it with least privilege."

# ---------------- 1. Identity ----------------
section "1. Identity"
check_eq 1.1 "hostname" "$EXPECTED_HOSTNAME" "$(hostnamectl --static 2>/dev/null || hostname)"
check_eq 1.1 "/etc/hostname" "$EXPECTED_HOSTNAME" "$(cat /etc/hostname 2>/dev/null)"
if [ -d /etc/cloud ]; then
  # later files override earlier ones: cloud.cfg first, then cloud.cfg.d/*.cfg in order
  ph=$(cat /etc/cloud/cloud.cfg /etc/cloud/cloud.cfg.d/*.cfg 2>/dev/null \
       | grep -E '^[[:space:]]*preserve_hostname:' | tail -n1 | awk '{print $2}')
  check_eq 1.1 "cloud-init preserve_hostname (survives reboot)" "true" "$ph"
else
  pass 1.1 "no cloud-init installed; hostname is not reset on boot"
fi

# ---------------- 2. Accounts and groups ----------------
section "2. Accounts and groups"
if getent passwd "$SERVICE_USER" >/dev/null; then
  check_eq 2.1 "$SERVICE_USER login shell" "/usr/sbin/nologin" "$(getent passwd "$SERVICE_USER" | cut -d: -f7)"
else
  fail 2.1 "service account $SERVICE_USER does not exist"
fi

want_ops=$(echo "$CURRENT_ENGINEERS $SERVICE_USER" | words_sorted)
got_ops=$(getent group "$OPS_GROUP" | cut -d: -f4 | words_sorted)
check_eq 2.2 "$OPS_GROUP members" "$want_ops" "$got_ops"

for e in $CURRENT_ENGINEERS; do
  if ! getent passwd "$e" >/dev/null; then fail 2.3 "engineer account $e does not exist"; continue; fi
  if id -nG "$e" | tr ' ' '\n' | grep -qx "$OPS_GROUP"; then pass 2.3 "$e is in $OPS_GROUP"
  else fail 2.3 "$e is not in $OPS_GROUP"; fi
  if has_sudo "$e"; then pass 2.3 "$e may use sudo"; else fail 2.3 "$e cannot use sudo"; fi
done

if getent passwd "$ASSESSOR" >/dev/null; then
  a_uid=$(id -u "$ASSESSOR"); a_shell=$(getent passwd "$ASSESSOR" | cut -d: -f7)
  a_groups=$(id -nG "$ASSESSOR" | words_sorted)
  if [ "$a_uid" = "$ASSESSOR_UID" ] && [ "$a_shell" = "$ASSESSOR_SHELL" ] \
     && [ "$a_groups" = "$ASSESSOR_GROUPS" ] && has_sudo "$ASSESSOR"; then
    pass 2.4 "$ASSESSOR unchanged (uid $a_uid, $a_shell, groups: $a_groups, sudo: yes)"
  else
    fail 2.4 "$ASSESSOR differs from baseline (uid $a_uid, $a_shell, groups: $a_groups) - do not 'fix' it, ask the CTO"
  fi
else
  fail 2.4 "assessor account $ASSESSOR is missing"
fi

for u in $FORMER_STAFF; do
  if ! getent passwd "$u" >/dev/null; then warn 2.5 "$u no longer exists (policy says lock, keep home)"; continue; fi
  home=$(getent passwd "$u" | cut -d: -f6)
  [ "$(passwd -S "$u" 2>/dev/null | awk '{print $2}')" = "L" ] \
    && pass 2.5 "$u password locked" || fail 2.5 "$u password not locked"
  exp=$(chage -l "$u" 2>/dev/null | awk -F': ' '/Account expires/{print $2}')
  [ -n "$exp" ] && [ "$exp" != "never" ] \
    && pass 2.5 "$u account expired ($exp)" || fail 2.5 "$u account never expires"
  id -nG "$u" | tr ' ' '\n' | grep -qx "$OPS_GROUP" \
    && fail 2.5 "$u still in $OPS_GROUP" || pass 2.5 "$u not in $OPS_GROUP"
  has_sudo "$u" && fail 2.5 "$u still has sudo" || pass 2.5 "$u has no sudo"
  if [ -e "$home/.ssh/authorized_keys" ] || [ -e "$home/.ssh/authorized_keys2" ]; then
    fail 2.5 "$u still has an active authorized_keys file"
  else pass 2.5 "$u has no active SSH keys"; fi
  crontab -l -u "$u" >/dev/null 2>&1 && fail 2.5 "$u still has a crontab" || pass 2.5 "$u has no crontab"
  [ -d "$home" ] && pass 2.5 "$u home folder kept as evidence ($home)" || fail 2.5 "$u home folder missing"
done

allowed_sudo="root $CURRENT_ENGINEERS $ASSESSOR"
for g in sudo admin wheel; do
  m=$(getent group "$g" | cut -d: -f4)
  if getent group "$g" >/dev/null && [ -n "$m" ]; then fail 2.6 "group $g has members ($m): sudo must come from /etc/sudoers.d only"
  else pass 2.6 "group $g gives nobody sudo"; fi
done
extra=""
while IFS=: read -r user _; do
  in_list "$user" "$allowed_sudo" && continue
  has_sudo "$user" && extra="$extra $user"
done < <(getent passwd)
[ -z "$extra" ] && pass 2.6 "only $allowed_sudo can use sudo" || fail 2.6 "unexpected sudo users:$extra"
named=$(grep -hEv '^[[:space:]]*(#|$|Defaults)' /etc/sudoers.d/* 2>/dev/null | awk '{print $1}' | words_sorted)
bad_named=""
for n in $named; do in_list "$n" "$allowed_sudo" || bad_named="$bad_named $n"; done
[ -z "$bad_named" ] && pass 2.6 "/etc/sudoers.d names only: ${named:-nobody}" \
                     || fail 2.6 "/etc/sudoers.d names non-staff:$bad_named"

# ---------------- 3. Files and permissions ----------------
section "3. Files and permissions"
while read -r pid path owner mode; do
  [ -z "${pid:-}" ] && continue
  if [ -e "$path" ]; then check_eq "$pid" "$path" "$owner $mode" "$(stat -c '%U:%G %a' "$path")"
  else fail "$pid" "$path is missing"; fi
done <<< "$PATH_RULES"
ww=$(find /opt/kente-app /var/log/kente-app /backups -perm -o+w 2>/dev/null | tr '\n' ' ')
[ -z "$ww" ] && pass 3.x "nothing world-writable under app, log or backup paths" \
             || fail 3.x "world-writable: $ww"

# ---------------- 4. Services ----------------
section "4. Services"
for svc in kente-app inventory-stub; do
  [ "$svc" = kente-app ] && pid_id=4.1 || pid_id=4.2
  check_eq "$pid_id" "$svc active" "active" "$(systemctl is-active "$svc" 2>/dev/null)"
  check_eq "$pid_id" "$svc enabled (starts after reboot)" "enabled" "$(systemctl is-enabled "$svc" 2>/dev/null)"
done
mainpid=$(systemctl show -p MainPID --value kente-app 2>/dev/null)
if [ -n "$mainpid" ] && [ "$mainpid" != "0" ]; then
  check_eq 4.1 "kente-app runs as" "$SERVICE_USER" "$(ps -o user= -p "$mainpid" | tr -d ' ')"
else
  fail 4.1 "kente-app has no running process"
fi
if ss -Htln | awk '{print $4}' | grep -qE ':8080$'; then pass 4.1 "something is listening on port 8080"
else fail 4.1 "nothing listening on port 8080"; fi

# ---------------- 5. Network ----------------
section "5. Network"
public=$(ss -Htln | awk '{print $4}' | grep -vE '^(127\.|\[::1\]|::1)' \
         | sed -E 's/.*:([0-9]+)$/\1/' | sort -un | tr '\n' ' ' | sed 's/ $//')
check_eq 5.1 "TCP ports listening on public addresses" "$ALLOWED_PUBLIC_TCP_PORTS" "$public"

if command -v ufw >/dev/null; then
  ufw_out=$(ufw status verbose 2>/dev/null)
  echo "$ufw_out" | grep -q '^Status: active' && pass 5.2 "ufw is active" || fail 5.2 "ufw is not active"
  echo "$ufw_out" | grep -q 'deny (incoming)' && pass 5.1 "ufw denies incoming by default" \
                                              || fail 5.1 "ufw does not deny incoming by default"
  rules=$(ufw status 2>/dev/null | awk '/ALLOW/{print $1}' | words_sorted)
  check_eq 5.1 "ufw ALLOW rules" "$(echo "$ALLOWED_UFW_RULES" | words_sorted)" "$rules"
else
  fail 5.2 "ufw is not installed"
fi
for fw in firewalld nftables; do
  systemctl is-active --quiet "$fw" 2>/dev/null && fail 5.2 "$fw is active (ufw must be the only firewall)" \
                                                 || pass 5.2 "$fw is not active"
done
if command -v iptables >/dev/null; then
  n=$(iptables -S 2>/dev/null | grep -vE '^-(P|N) |ufw' | wc -l)
  [ "$n" -eq 0 ] && pass 5.2 "no iptables rules outside ufw" || fail 5.2 "$n iptables rule(s) not managed by ufw"
fi

resolved=$(getent hosts "$INVENTORY_HOST" | awk '{print $1}' | head -n1)
check_eq 5.3 "$INVENTORY_HOST resolves to" "127.0.0.1" "$resolved"
n_entries=$(grep -cE "^[^#]*[[:space:]]$INVENTORY_HOST([[:space:]]|$)" /etc/hosts)
check_eq 5.3 "/etc/hosts entries for $INVENTORY_HOST" "1" "$n_entries"

resp=$(curl -s -m 5 -w '\n%{http_code}' "$HEALTH_URL" 2>/dev/null)
code=$(echo "$resp" | tail -n1); body=$(echo "$resp" | head -n1)
if [ "$code" = "200" ] && [ "$body" = "ok" ]; then pass 5.4 "$HEALTH_URL returns ok (200)"
else fail 5.4 "$HEALTH_URL returned '${body}' (HTTP ${code:-none})"; fi

# ---------------- 6. Logs ----------------
section "6. Logs"
if [ -f "$APP_LOG" ]; then
  pass 6.2 "current log $APP_LOG exists"
  # Only lines written since the running app started, so old lines from a
  # previous version don't cause false FAILs.
  started=$(systemctl show -p ActiveEnterTimestamp --value kente-app 2>/dev/null)
  since=$(date -d "$started" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "0000-00-00 00:00:00")
  recent=$(awk -v s="$since" '($1 " " $2) >= s' "$APP_LOG")
  total=$(printf '%s\n' "$recent" | sed '/^$/d' | wc -l)
  bad=$(printf '%s\n' "$recent" | sed '/^$/d' | grep -Evc \
        '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} [^ ]+ [A-Z]+ [^ ]+ [0-9]{3} [0-9]+ms [^ ]+$')
  if [ "$bad" -eq 0 ]; then pass 6.1 "all $total log lines since $since have the 8 policy fields"
  else fail 6.1 "$bad of $total log lines since $since do not have the 8 policy fields"; fi
else
  fail 6.2 "current log $APP_LOG is missing"
fi
refs=$(grep -RlsE 'access\.log' /etc/cron* /var/spool/cron/crontabs /etc/logrotate.d /etc/systemd/system 2>/dev/null | tr '\n' ' ')
[ -z "$refs" ] && pass 6.2 "no scheduled job touches access.log" \
               || warn 6.2 "review these jobs: they mention access.log (today's log must never be deleted): $refs"

# ---------------- Load-bearing guards (handover, not in the policy) ----------------
section "Handover guards"
if [ -e /etc/cron.d/kente-maintenance ]; then
  if find /backups -type f -mtime -2 2>/dev/null | grep -q .; then
    pass LB.1 "maintenance is scheduled and /backups has a backup from the last 2 days"
  else
    fail LB.1 "maintenance is scheduled but /backups has no recent backup: it will delete snapshots that were never backed up"
  fi
else
  pass LB.1 "maintenance not scheduled (on hold until a backup job exists)"
fi

# ---------------- Summary ----------------
printf '\nSummary: %d PASS, %d FAIL, %d WARN\n' "$PASS" "$FAIL" "$WARN"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1