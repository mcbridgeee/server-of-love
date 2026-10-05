# hardening server-of-love

step-by-step security for the droplet (issue #2). run these over ssh on the droplet, in order. every step says how to check it worked and how to undo it. nothing secret lives in this repo: passwords and keys are created on the droplet and stay there.

first pull this repo on the droplet so the files below exist:

```bash
cd ~/server-of-love && git pull
```

| step | protects against | risk if done wrong |
| --- | --- | --- |
| 1. ssh keys only | password guessing | **locking yourself out** (read step 1 twice) |
| 2. firewall | stray open ports | locking out ssh if 22 isn't allowed first |
| 3. dashboard password | anyone reading your traefik setup | none |
| 4. fail2ban | repeat ssh guessers, request floods | banning yourself (unban command below) |
| 5. security updates | known ubuntu bugs | none |

## 1. ssh: keys only

**before anything:** open a *second* terminal and log in to the droplet. leave it open the whole time. if a change breaks ssh, you fix it from that session. digitalocean's web console (droplet → access → launch droplet console) is the last-resort way in.

check that your key login works on its own, from your own computer:

```bash
ssh -o PasswordAuthentication=no -o PubkeyAuthentication=yes <you>@<droplet-ip> echo key-login-ok
```

only if that prints `key-login-ok`:

```bash
sudo cp ~/server-of-love/security/ssh/10-server-of-love.conf /etc/ssh/sshd_config.d/
sudo sshd -t && echo "config ok"          # stop here if this prints an error
sudo systemctl reload ssh
```

check from a *new* terminal (keep the old ones open):

```bash
ssh <you>@<droplet-ip> echo still-in                                    # works with your key
ssh -o PubkeyAuthentication=no <you>@<droplet-ip>                       # must say "Permission denied (publickey)"
sudo sshd -T | grep -E "passwordauthentication|permitrootlogin"         # no / prohibit-password
```

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

right now anyone can open the dashboard and read your routing setup. this follows 373_hosting chapter 5, but as an overlay file so regenerating the stack can't drop it.

```bash
sudo apt-get install -y apache2-utils
cd ~/373_hosting
sudo install -d -m 700 runtime/secrets
sudo htpasswd -cB runtime/secrets/dashboard.htpasswd admin     # it asks for the password; nothing lands in your shell history
sudo chmod 600 runtime/secrets/dashboard.htpasswd
sudo docker compose -f runtime/compose.yaml -f ~/server-of-love/hosting/compose.security.yaml config --quiet && echo "config ok"
sudo docker compose -f runtime/compose.yaml -f ~/server-of-love/hosting/compose.security.yaml up -d
```

check (use your dashboard hostname):

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://<dashboard-host>/dashboard/                      # 401
curl -s -o /dev/null -w "%{http_code}\n" -u admin https://<dashboard-host>/dashboard/             # asks for the password, then 200
```

**from now on, every hosting-stack command needs both `-f` files** (or the password disappears):
`sudo docker compose -f runtime/compose.yaml -f ~/server-of-love/hosting/compose.security.yaml <command>`

rehearsed in a sandbox: no password → 401, wrong password → 401, right password → 200.

## 4. fail2ban: ban ips that misbehave

two jails:

- **sshd:** 5 failed ssh logins in 10 minutes → banned for 1 hour
- **traefik-quiz-ratelimit:** traefik already answers `429 Too Many Requests` when one ip floods the quiz (more than 50 requests/second sustained, bursts up to 100). an ip that piles up **300 of those 429s within a minute** is banned from the whole server's websites for 10 minutes

the limits are loose on purpose. a whole classroom shares one public ip. in the rehearsal, 30 people loading the quiz at the same moment got 90 out of 90 normal responses, while a script sending 600 requests in 4 seconds got 303 `429`s.

the quiz route needs the rate limit first. that lives in `integrations/quiz/compose.traefik.yaml`, so re-copy it into the quiz checkout and redeploy:

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

## 5. automatic security updates

ubuntu 24.04 usually has this on already. check:

```bash
systemctl is-enabled unattended-upgrades                 # enabled
cat /etc/apt/apt.conf.d/20auto-upgrades                  # both lines "1"
```

if not:

```bash
sudo apt-get install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades          # answer yes
```

this patches ubuntu packages only. container images (traefik, apache, the quiz) update separately; the quiz updates through its ci/cd pipeline.

## record it

when each step is done, tick its box on issue #2 with the check output (no passwords, no keys, no full ip lists).
