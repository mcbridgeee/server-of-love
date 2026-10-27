# server-of-love

my first self-hosted web server, built for is373. one ubuntu droplet on digitalocean runs two websites, the calculator and quiz app from [is373-ci-cd](https://github.com/mcbridgeee/is373-ci-cd), and a traefik dashboard, each on its own hostname with automatic https.

| hostname | what's there |
| --- | --- |
| [bmctiernan.com](https://bmctiernan.com) | calculator, production: the [is373-ci-cd](https://github.com/mcbridgeee/is373-ci-cd) app's `prod` container (browser vs. server, "results match") |
| [www.bmctiernan.com](https://www.bmctiernan.com) | lavender welcome page |
| [report.bmctiernan.com](https://report.bmctiernan.com) | blue lab report: request path, dns, verification, dashboard, controlled failure, backup plan |
| [quiz.bmctiernan.com](https://quiz.bmctiernan.com) | toothpaste quiz from the same app and container, auto-updated by its ci/cd pipeline |
| [calc.bmctiernan.com](https://calc.bmctiernan.com) | the production calculator again, same container |
| [qa.bmctiernan.com](https://qa.bmctiernan.com) | calculator, QA: the app's separate `qa` container, updated from its `qa` branch |

## how it works

a visitor's browser asks dns for the name, dns points it at the droplet, and traefik (a reverse proxy) handles https and reads the hostname to pick the right container. www and report are apache containers serving one `index.html` each. bmctiernan.com, quiz, calc, and qa go to the is373-ci-cd app's containers instead.

the server is set up with my instructor's [373_hosting](https://github.com/kaw393939/373_hosting) scripts. this repo holds only my own work: the pages in `sites/`.

## what's in here

```
sites/
  bmctiernan.com/index.html (the old pink welcome page, kept but not served: the app's route wins)
  www.bmctiernan.com/index.html
  report.bmctiernan.com/index.html (+ dashboard.png, failure-404.png)
integrations/quiz/     original traefik route for the quiz and calc, with a rate limit (see "the quiz app" below)
hosting/               password on the traefik dashboard (overlay) + compose.sh, which always applies it
security/              hardening runbook, check.sh (read-only audit), and fail2ban / ssh / update config for the droplet
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

the quiz isn't an apache site. it's a container image built, tested, and published by [is373-ci-cd](https://github.com/mcbridgeee/is373-ci-cd), then pulled here. the live traefik routes (bmctiernan.com, quiz, calc, qa) come from that repo's [deploy/compose.traefik.yaml](https://github.com/mcbridgeee/is373-ci-cd/blob/main/deploy/compose.traefik.yaml). `integrations/quiz/` is the original quiz and calc adapter, which doesn't have the bmctiernan.com or qa routes. the step-by-step lives in the app repo's [docs/hosting.md](https://github.com/mcbridgeee/is373-ci-cd/blob/main/docs/hosting.md).

## security

[security/README.md](security/README.md) hardens the droplet step by step: no root login over ssh and keys only, firewall, a dashboard password, fail2ban (bans repeat ssh guessers and ips that keep flooding the quiz after traefik rate-limits them), and security updates every night at 2am. each step has a check and an undo, and the top of that file maps each of the instructor's requirements to where it lives.

## never committed

`acme.json` (certificates and the let's encrypt account key), the real `hosting.json`, ssh keys, passwords, and `dashboard.htpasswd`. `.gitignore` blocks the common ones.
