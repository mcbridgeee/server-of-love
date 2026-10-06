# hardening server-of-love

step-by-step security for the droplet (issue #2). run these over ssh on the droplet, in order. every step says how to check it worked and how to undo it. nothing secret lives in this repo: passwords and keys are created on the droplet and stay there.

first pull this repo on the droplet so the files below exist:

```bash
cd ~/server-of-love && git pull
```

## instructor requirements → where they are

| requirement | where | step |
| --- | --- | --- |
| fail2ban blocks people after x failed attempts | `security/fail2ban/` | 4 |
| security updates every night at 2am | `security/updates/`, `security/systemd/apt-daily*-timer.conf` | 5 |
| no root login over ssh | `security/ssh/10-server-of-love.conf` | 1 |
| security scanner (trivy) in the github action that deploys the image | is373-ci-cd `.github/workflows/ci.yml` (issue #16) | n/a |
| hardened dockerfile | is373-ci-cd `Dockerfile` (issue #5) | n/a |
| push to deploy: github → docker hub → server updates itself | is373-ci-cd ci/cd + WUD, `docs/hosting.md` (issues #6, #7, #18) | n/a |

| step | protects against | risk if done wrong |
| --- | --- | --- |
| 1. your own user, no root ssh, keys only | password guessing, root takeover | **locking yourself out** (read step 1 twice) |
| 2. firewall | stray open ports | locking out ssh if 22 isn't allowed first |
| 3. dashboard password | anyone reading your traefik setup | none |
| 4. fail2ban | repeat ssh guessers, request floods | banning yourself (unban command below) |
| 5. nightly security updates at 2am | known ubuntu bugs | a short reboot at 2:30 when an update needs one |

## 1. ssh: your own user, no root login, keys only

**before anything:** open a *second* terminal and log in to the droplet. leave it open the whole time. if a change breaks ssh, you fix it from that session. digitalocean's web console (droplet → access → launch droplet console) is the last-resort way in; it isn't ssh, so it still works after this step.

### 1a. your own sudo user: already done on this droplet

checked 2026-10-06: user `bridge` exists, is in the `sudo` group, `sudo` works with its password, and `ssh bridge@192.241.153.53` logs in with your key. your repos live in `/home/bridge` (`373_hosting`, `server-of-love`, `is373-ci-cd`).

from now on, log in as `bridge` and put `sudo` in front of admin commands. don't use `sudo -i` for these steps: it switches to root's home, where none of your folders are.

(on a fresh server you'd make the user first: `adduser bridge`, `usermod -aG sudo bridge`, `rsync --archive --chown=bridge:bridge ~/.ssh /home/bridge`, then test `ssh bridge@<ip> 'sudo whoami'` prints `root`.)

### 1b. turn off root login and passwords

check that key login works on its own, from your own computer:

```bash
ssh -o PasswordAuthentication=no -o PubkeyAuthentication=yes bridge@192.241.153.53 echo key-login-ok
```

only if that prints `key-login-ok`:

```bash
sudo cp ~/server-of-love/security/ssh/10-server-of-love.conf /etc/ssh/sshd_config.d/
sudo sshd -t && echo "config ok"          # stop here if this prints an error
sudo systemctl reload ssh
```

check from a *new* terminal (keep the old ones open):

```bash
ssh bridge@192.241.153.53 echo still-in                                  # works with your key
ssh root@192.241.153.53                                                   # must say "Permission denied (publickey)"
ssh -o PubkeyAuthentication=no bridge@192.241.153.53                    # must say "Permission denied (publickey)"
sudo sshd -T | grep -E "passwordauthentication|permitrootlogin"         # passwordauthentication no, permitrootlogin no
```

the root and password checks above are *failed logins on purpose*. fail2ban (step 4) bans an ip after 5 failed logins in 10 minutes, and ssh can count one failure per key it tries. so run these checks only now, before step 4, and don't repeat them from home afterwards. on 2026-10-06 repeating them after step 4 banned my own home ip from ssh for an hour (the websites kept working). if that happens: wait an hour, use a phone hotspot, or open the digitalocean droplet console, change the end of its address from `?os_user=root` to `?os_user=bridge` (root is refused now), and run `sudo fail2ban-client set sshd unbanip <your ip>`. a `Host droplet` entry in your laptop's `~/.ssh/config` with `User bridge`, `IdentityFile`, and `IdentitiesOnly yes` keeps normal logins from ever counting.

the file is named `10-…` because sshd keeps the first value it reads. digitalocean's `50-cloud-init.conf` can say `PasswordAuthentication yes`, and ours has to win. rehearsed with ubuntu 24.04's own sshd (openssh 9.6p1): with a cloud-init file saying yes to both, the effective settings were `permitrootlogin no`, `passwordauthentication no`, `maxauthtries 3`.

undo: `sudo rm /etc/ssh/sshd_config.d/10-server-of-love.conf && sudo systemctl reload ssh`

## 2. firewall (ufw)

allow ssh **before** turning the firewall on:

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable
sudo ufw status verbose
```

docker-published ports skip ufw, so also check what's actually listening:

```bash
sudo ss -tlnp
```

only `:22`, `:80`, `:443` should be on `0.0.0.0` / `[::]`. the quiz (`127.0.0.1:8090`) and its updater (`127.0.0.1:8091`) must say `127.0.0.1`.

undo: `sudo ufw disable`

## 3. password on the traefik dashboard

right now anyone can open `https://traefik.bmctiernan.com/dashboard/` and read your routing setup: every hostname, router, service, and container port. it can't change anything, but it's a free map for an attacker. the instructor left it open for the class demo; chapter 5 shows how to lock it. this does exactly that, as an overlay file so regenerating the stack can't drop it.

**about 10 minutes.** as `bridge`:

```bash
sudo apt-get install -y apache2-utils
cd ~/373_hosting
sudo install -d -m 700 runtime/secrets
sudo htpasswd -cB runtime/secrets/dashboard.htpasswd admin     # it asks for a NEW dashboard password (sudo may ask for bridge's first); nothing lands in your shell history
sudo chmod 600 runtime/secrets/dashboard.htpasswd
sudo ~/server-of-love/hosting/compose.sh config --quiet && echo "config ok"
sudo ~/server-of-love/hosting/compose.sh up -d
```

`hosting/compose.sh` is plain `docker compose` with both files (`runtime/compose.yaml` + `hosting/compose.security.yaml`) already filled in, and it refuses to run if the password file is missing. **from now on use it for every hosting-stack command** (`compose.sh ps`, `compose.sh up -d`, `compose.sh logs traefik`). A bare `docker compose -f runtime/compose.yaml up -d` would quietly remove the password again.

check, from your own computer:

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://traefik.bmctiernan.com/dashboard/               # 401
curl -s -o /dev/null -w "%{http_code}\n" -u admin https://traefik.bmctiernan.com/dashboard/      # asks for the password, then 200
```

and in a browser: the dashboard now pops up a login box. use `admin` and your password.

undo: `cd ~/373_hosting && sudo docker compose -f runtime/compose.yaml up -d` (without the overlay).

rehearsed in a sandbox: no password → 401, wrong password → 401, right password → 200; the wrapper refuses to run without the password file.

## 4. fail2ban: ban ips that misbehave

two jails:

- **sshd:** 5 failed ssh logins in 10 minutes → banned for 1 hour
- **traefik-quiz-ratelimit:** traefik already answers `429 Too Many Requests` when one ip floods the quiz (more than 50 requests/second sustained, bursts up to 100). an ip that piles up **300 of those 429s within a minute** is banned from the whole server's websites for 10 minutes

the limits are loose on purpose. a whole classroom shares one public ip. in the rehearsal, 30 people loading the quiz at the same moment got 90 out of 90 normal responses, while a script sending 600 requests in 4 seconds got 303 `429`s.

the quiz route needs the rate limit first. it lives in `integrations/quiz/compose.traefik.yaml`; if you deployed on or after 2026-10-06 it's already in place and you can skip this block. otherwise re-copy it and redeploy:

```bash
cp ~/server-of-love/integrations/quiz/compose.traefik.yaml ~/is373-ci-cd/compose.override.yaml
cd ~/is373-ci-cd && sudo make deploy
```

then install fail2ban:

```bash
sudo apt-get install -y fail2ban python3-systemd
sudo cp ~/server-of-love/security/fail2ban/filter.d/traefik-quiz-ratelimit.conf /etc/fail2ban/filter.d/
sudo cp ~/server-of-love/security/fail2ban/jail.d/server-of-love.local /etc/fail2ban/jail.d/
sudo install -D -m 644 ~/server-of-love/security/systemd/fail2ban-after-docker.conf /etc/systemd/system/fail2ban.service.d/after-docker.conf
sudo systemctl daemon-reload
sudo fail2ban-client -t && echo "config ok"
sudo systemctl enable --now fail2ban
sudo systemctl restart fail2ban
```

check:

```bash
sudo fail2ban-client status                               # Jail list: sshd, traefik-quiz-ratelimit
sudo fail2ban-client status traefik-quiz-ratelimit        # File list shows the docker log files
sudo fail2ban-client status sshd                          # likely already has bans: bots try ssh all day
```

**why the extra `DOCKER-USER` setting:** traffic to docker containers (traefik's 80/443) never passes the firewall chain fail2ban normally uses, so a normal ban would quietly do nothing. the jail puts its bans in `DOCKER-USER`, which docker checks first. rehearsed: a banned outside client got `connection refused` while everyone else kept getting `200`, and unbanning let it back in.

**after the hosting stack's traefik is recreated** (an upgrade, or regenerating the stack), run `sudo fail2ban-client reload` so it picks up traefik's new log file.

### banned yourself?

```bash
sudo fail2ban-client status traefik-quiz-ratelimit        # see "Banned IP list"
sudo fail2ban-client set traefik-quiz-ratelimit unbanip <ip>
sudo fail2ban-client set sshd unbanip <ip>                # from the open session or the web console
```

### showing it in class

don't flood from the classroom. you'd ban the whole room's shared ip, possibly including your instructor, for 10 minutes. instead:

```bash
sudo fail2ban-client status sshd                                   # real bans from internet bots
sudo fail2ban-client status traefik-quiz-ratelimit
sudo fail2ban-client set traefik-quiz-ratelimit banip 203.0.113.7  # a reserved documentation-only ip
sudo iptables -S | grep f2b                                         # the ban as a firewall rule
sudo fail2ban-client set traefik-quiz-ratelimit unbanip 203.0.113.7
```

and to show the rate limit itself, from a **phone hotspot** (not the classroom wifi):

```bash
seq 300 | xargs -P 50 -I{} curl -s -o /dev/null -w "%{http_code}\n" https://quiz.bmctiernan.com/health | sort | uniq -c
```

you'll see a mix of `200` and `429`. that stays under the ban threshold.

## 5. security updates every night at 2am

ubuntu's `unattended-upgrades` installs security updates, but by default at a random time each morning. these files pin it to **2:00 every night** (package lists download at 1:30), and reboot at 2:30 **only if** an update needs it (kernel, libc). everything comes back by itself after a reboot: traefik and the sites, the quiz, WUD (`restart: unless-stopped`), and fail2ban (started after docker).

set the droplet's clock to your time zone first, so "2am" means 2am for you (droplets start on UTC):

```bash
sudo timedatectl set-timezone America/New_York
timedatectl | grep "Time zone"
```

then:

```bash
sudo apt-get install -y unattended-upgrades
sudo cp ~/server-of-love/security/updates/20auto-upgrades /etc/apt/apt.conf.d/20auto-upgrades
sudo cp ~/server-of-love/security/updates/52-server-of-love-unattended-upgrades /etc/apt/apt.conf.d/
sudo install -D -m 644 ~/server-of-love/security/systemd/apt-daily-timer.conf /etc/systemd/system/apt-daily.timer.d/server-of-love.conf
sudo install -D -m 644 ~/server-of-love/security/systemd/apt-daily-upgrade-timer.conf /etc/systemd/system/apt-daily-upgrade.timer.d/server-of-love.conf
sudo systemctl daemon-reload
sudo systemctl restart apt-daily.timer apt-daily-upgrade.timer
```

check:

```bash
systemctl list-timers 'apt-daily*'                       # NEXT: tonight 01:30 and 02:00
apt-config dump | grep -E "Periodic::(Update-Package-Lists|Unattended-Upgrade)|Automatic-Reboot"
sudo unattended-upgrade --dry-run --debug 2>&1 | tail -5  # what it would install right now
```

after the first night, show it ran:

```bash
sudo tail -20 /var/log/unattended-upgrades/unattended-upgrades.log
```

undo: `sudo rm -r /etc/systemd/system/apt-daily*.timer.d && sudo systemctl daemon-reload` (back to ubuntu's random morning time).

this patches ubuntu packages only. the quiz image gets its security fixes through its ci/cd pipeline (weekly dependabot base-image updates plus a trivy scan on every build), and a daily scan of the live image.

## check everything at once

`security/check.sh` is read-only: it changes nothing and prints `PASS` / `FAIL` / `WARN` for every item above, plus the quiz deploy. run it after each step, and once at the end:

```bash
sudo ~/server-of-love/security/check.sh
```

the end goal is `all required checks passed`. paste the output into issue #2; it prints no secrets. it's also the fastest thing to show your instructor.

## record it

when each step is done, tick its box on issue #2 with the check output (no passwords, no keys, no full ip lists).
