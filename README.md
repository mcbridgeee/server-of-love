# server-of-love

my first self-hosted web server, built for is373. one ubuntu droplet on digitalocean runs three websites, a quiz app, and a traefik dashboard, each on its own hostname with automatic https.

| hostname | what's there |
| --- | --- |
| [bmctiernan.com](https://bmctiernan.com) | pink welcome page |
| [www.bmctiernan.com](https://www.bmctiernan.com) | lavender welcome page |
| [report.bmctiernan.com](https://report.bmctiernan.com) | blue lab report: request path, dns, verification, dashboard, controlled failure, backup plan |
| [quiz.bmctiernan.com](https://quiz.bmctiernan.com) | toothpaste quiz app from [is373-ci-cd](https://github.com/mcbridgeee/is373-ci-cd), auto-updated by its ci/cd pipeline |

## how it works

a visitor's browser asks dns for the name, dns points it at the droplet, and traefik (a reverse proxy) handles https and reads the hostname to pick the right container. each site is its own apache container serving one `index.html`.

the server is set up with my instructor's [373_hosting](https://github.com/kaw393939/373_hosting) scripts. this repo holds only my own work: the pages in `sites/`.

## what's in here

```
sites/
  bmctiernan.com/index.html
  www.bmctiernan.com/index.html
  report.bmctiernan.com/index.html (+ dashboard.png, failure-404.png)
integrations/quiz/     traefik route for the quiz app (copied into the app's checkout), with a rate limit
hosting/               overlay for the hosting stack: password on the traefik dashboard
security/              hardening runbook + fail2ban, ssh, systemd config to copy onto the droplet
deploy.sh              copies pages to the live site folders
hosting.example.json   template of the settings file (the real one stays private)
```

## editing and deploying

this repo is cloned on the server at `~/server-of-love`. edit a page there, then:

```bash
./deploy.sh                       # copy pages into the live site folders
git add -A && git commit -m "..."  # save a snapshot
git push                           # back it up to github
```

the live pages are served from `~/373_hosting/runtime/sites/<hostname>/`, and changes show up on refresh with no restart.

## the quiz app

the quiz isn't an apache site. it's a container image built, tested, and published by [is373-ci-cd](https://github.com/mcbridgeee/is373-ci-cd), then pulled here. `integrations/quiz/` is the small adapter that connects it to traefik. the step-by-step lives in the app repo's [docs/hosting.md](https://github.com/mcbridgeee/is373-ci-cd/blob/main/docs/hosting.md).

## security

[security/README.md](security/README.md) hardens the droplet step by step: ssh keys only, firewall, a dashboard password, fail2ban (bans repeat ssh guessers and ips that keep flooding the quiz after traefik rate-limits them), and automatic security updates. each step has a check and an undo.

## never committed

`acme.json` (certificates and the let's encrypt account key), the real `hosting.json`, ssh keys, passwords, and `dashboard.htpasswd`. `.gitignore` blocks the common ones.
