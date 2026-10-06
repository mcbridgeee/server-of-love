#!/usr/bin/env bash
# Read-only audit of the droplet against the hardening requirements.
# Changes nothing. Run on the droplet as root:
#
#   sudo ~/server-of-love/security/check.sh
#
# Prints PASS / FAIL / WARN per item and exits non-zero if anything FAILs.
# Safe to paste the output into issue #2: it prints no secrets.
set -u

QUIZ_HOST=${QUIZ_HOST:-quiz.bmctiernan.com}
CALC_HOST=${CALC_HOST:-calc.bmctiernan.com}
DASHBOARD_HOST=${DASHBOARD_HOST:-traefik.bmctiernan.com}
SITES=${SITES:-"bmctiernan.com www.bmctiernan.com report.bmctiernan.com"}
fails=0

pass() { printf 'PASS  %-34s %s\n' "$1" "$2"; }
fail() { printf 'FAIL  %-34s %s\n' "$1" "$2"; fails=$((fails + 1)); }
warn() { printf 'WARN  %-34s %s\n' "$1" "$2"; }
has()  { command -v "$1" >/dev/null 2>&1; }

[ "$(id -u)" -eq 0 ] || { echo "run with sudo: sudo $0" >&2; exit 2; }

echo "== 1. fail2ban (instructor requirement 1)"
if systemctl is-active --quiet fail2ban 2>/dev/null; then
  pass "fail2ban running" "$(fail2ban-client version 2>/dev/null | head -1)"
  jails=$(fail2ban-client status 2>/dev/null | sed -n 's/.*Jail list:[[:space:]]*//p')
  for jail in sshd traefik-quiz-ratelimit; do
    if printf '%s' "$jails" | grep -qw "$jail"; then
      banned=$(fail2ban-client status "$jail" 2>/dev/null | sed -n 's/.*Total banned:[[:space:]]*//p')
      pass "jail $jail" "total banned so far: ${banned:-0}"
    else
      fail "jail $jail" "not loaded (security/README.md step 4)"
    fi
  done
  if iptables -S DOCKER-USER 2>/dev/null | grep -q 'f2b-traefik-quiz-ratelimit'; then
    pass "quiz bans reach docker ports" "f2b chain hooked into DOCKER-USER"
  else
    warn "quiz bans reach docker ports" "no f2b hook in DOCKER-USER yet: fail2ban adds it at this jail's first ban (test: fail2ban-client set traefik-quiz-ratelimit banip 203.0.113.7, then unbanip)"
  fi
else
  fail "fail2ban running" "not active (security/README.md step 4)"
fi

echo "== 2. security updates nightly at 2am (instructor requirement 2)"
tz=$(timedatectl show -p Timezone --value 2>/dev/null)
[ "$tz" = "America/New_York" ] && pass "time zone" "$tz" || warn "time zone" "${tz:-unknown} (2am means 2am in this zone)"
if systemctl show apt-daily-upgrade.timer -p TimersCalendar 2>/dev/null | grep -q '02:00:00'; then
  next=$(systemctl show apt-daily-upgrade.timer -p NextElapseUSecRealtime --value 2>/dev/null)
  pass "upgrade timer at 02:00" "next: ${next:-?}"
else
  fail "upgrade timer at 02:00" "still on ubuntu's default schedule (step 5)"
fi
if apt-config dump 2>/dev/null | grep -q 'APT::Periodic::Unattended-Upgrade "1"'; then
  pass "unattended-upgrades enabled" "APT::Periodic::Unattended-Upgrade 1"
else
  fail "unattended-upgrades enabled" "APT::Periodic::Unattended-Upgrade not 1 (step 5)"
fi
apt-config dump 2>/dev/null | grep -q 'Unattended-Upgrade::Automatic-Reboot "true"' \
  && pass "reboot when needed" "at $(apt-config dump 2>/dev/null | sed -n 's/.*Automatic-Reboot-Time "\(.*\)";/\1/p')" \
  || warn "reboot when needed" "automatic reboot off: kernel fixes wait for a manual reboot"
log=/var/log/unattended-upgrades/unattended-upgrades.log
[ -s "$log" ] && pass "has run before" "last: $(grep -m1 -o '^[0-9-]* [0-9:]*' <(tac "$log") 2>/dev/null)" \
  || warn "has run before" "no log yet (normal before the first night)"

echo "== 3. ssh: no root login, keys only (instructor requirement 3)"
sshd_t=$(sshd -T 2>/dev/null)
v=$(printf '%s\n' "$sshd_t" | awk '$1=="permitrootlogin"{print $2}')
[ "$v" = "no" ] && pass "root login over ssh" "permitrootlogin no" || fail "root login over ssh" "permitrootlogin ${v:-?} (step 1)"
v=$(printf '%s\n' "$sshd_t" | awk '$1=="passwordauthentication"{print $2}')
[ "$v" = "no" ] && pass "password login over ssh" "passwordauthentication no" || fail "password login over ssh" "passwordauthentication ${v:-?} (step 1)"

echo "== firewall and open ports"
has ss || { fail "ss available" "install iproute2 to check listening ports"; }
if has ufw && ufw status 2>/dev/null | grep -q 'Status: active'; then
  pass "ufw" "active: $(ufw status 2>/dev/null | awk '/ALLOW/ && !/\(v6\)/{print $1}' | sort -u | tr '\n' ' ')"
else
  fail "ufw" "not active (step 2)"
fi
public=$(ss -Htln 2>/dev/null | awk '{print $4}' | grep -vE '^(127\.|\[::1\]|::1)' | sed 's/.*://' | sort -un | tr '\n' ' ')
extra=$(printf '%s\n' $public | grep -vxE '22|80|443' | tr '\n' ' ')
has ss && { [ -z "$extra" ] && pass "public listening ports" "${public:-none}" || fail "public listening ports" "unexpected: $extra (all: $public)"; }
has ss && for port in 8090 8091; do
  bind=$(ss -Htln "sport = :$port" 2>/dev/null | awk '{print $4}' | head -1)
  case "$bind" in
    "") warn "port $port" "nothing listening (quiz not deployed?)" ;;
    127.0.0.1:*) pass "port $port loopback only" "$bind" ;;
    *) fail "port $port loopback only" "listening on $bind" ;;
  esac
done

echo "== traefik dashboard password"
code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "https://$DASHBOARD_HOST/dashboard/")
case "$code" in
  401) pass "dashboard needs a login" "https://$DASHBOARD_HOST/dashboard/ -> 401" ;;
  200) fail "dashboard needs a login" "open to anyone: 200 (step 3)" ;;
  *)   warn "dashboard needs a login" "got $code (wrong DASHBOARD_HOST?)" ;;
esac

echo "== quiz: push-to-deploy target (instructor requirement 5)"
health=$(curl -s -m 10 "https://$QUIZ_HOST/health")
if printf '%s' "$health" | grep -q '"environment":"production"'; then
  pass "quiz live over https" "commit $(printf '%s' "$health" | sed -n 's/.*"commit":"\([0-9a-f]\{7\}\).*/\1/p')"
else
  fail "quiz live over https" "no production /health at https://$QUIZ_HOST (docs/hosting.md)"
fi
headers=$(curl -s -m 10 -D - -o /dev/null "https://$QUIZ_HOST/")
printf '%s' "$headers" | grep -qi '^strict-transport-security' && pass "quiz HSTS" "present" || warn "quiz HSTS" "missing (adapter not applied?)"
printf '%s' "$headers" | grep -qi '^content-security-policy' && pass "quiz CSP" "present" || warn "quiz CSP" "missing"
if curl -s -m 10 "https://$CALC_HOST/" | grep -q '<h1>Calculator</h1>'; then
  answer=$(curl -s -m 10 -H 'Content-Type: application/json' -d '{"a":6,"b":7,"operation":"multiply"}' "https://$CALC_HOST/api/calculate")
  [ "$answer" = '{"result":42.0}' ] && pass "calculator live over https" "https://$CALC_HOST: 6 x 7 = 42" \
    || fail "calculator live over https" "page loads but /api/calculate answered: ${answer:-nothing}"
else
  fail "calculator live over https" "no calculator at https://$CALC_HOST (DNS record? adapter re-copied?)"
fi
if has docker && docker inspect is373-ci-cd-prod-1 --format '{{json .Config.Labels}}' 2>/dev/null | grep -q 'quiz-ratelimit'; then
  pass "quiz rate limit" "middleware on the route"
else
  warn "quiz rate limit" "not on the running container (re-copy the adapter, make deploy)"
fi
if has docker && [ "$(docker inspect -f '{{.State.Running}}' is373-ci-cd-wud-1 2>/dev/null)" = "true" ]; then
  pass "auto-updater (WUD)" "running"
else
  warn "auto-updater (WUD)" "not running (paused for a rollback, or not deployed)"
fi
for site in $SITES; do
  code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "https://$site/")
  [ "$code" = 200 ] && pass "site $site" "200" || warn "site $site" "$code"
done

echo
if [ "$fails" -eq 0 ]; then echo "all required checks passed"; else echo "$fails check(s) failed"; fi
exit $((fails > 0))
