# quiz routing adapter

Connects the [toothpaste quiz and calculator](https://github.com/mcbridgeee/is373-ci-cd) to this server's Traefik at `https://quiz.bmctiernan.com` and `https://calc.bmctiernan.com`. One container serves both; on `calc.`, Traefik maps `/` to the app's `/calc` page. It holds no app code, Dockerfile, or deploy logic; those live in the quiz repo.

| file | goes to | job |
| --- | --- | --- |
| `compose.traefik.yaml` | `~/is373-ci-cd/compose.override.yaml` | puts only `prod` on `hosting-web`, adds the quiz and calc Host rules, rate limit, HSTS, port 8000 |
| `.env.example` | `~/is373-ci-cd/.env` | picks the hostname and the proxy network |

The full step-by-step (DNS, clone, deploy, checks, rollback) is in the quiz repo's [docs/hosting.md](https://github.com/mcbridgeee/is373-ci-cd/blob/main/docs/hosting.md).

## rules

- add a DNS A record for `calc` (same ip as `quiz`)
- don't add `quiz.bmctiernan.com` or `calc.bmctiernan.com` to `hosting.json` `sites`. That makes an Apache router competing for the same name
- don't give WUD (the quiz's updater) a Traefik route. Its dashboard stays on `127.0.0.1:8091`; reach it with `ssh -L 8091:127.0.0.1:8091 ...`
- the quiz keeps `127.0.0.1:8090` for local checks; nothing new is opened to the internet
