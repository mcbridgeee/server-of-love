# server-of-love

my first self-hosted web server, built for is373. one ubuntu droplet on digitalocean runs three websites and a traefik dashboard, each on its own hostname with automatic https.

| hostname | what's there |
| --- | --- |
| [bmctiernan.com](https://bmctiernan.com) | pink welcome page |
| [www.bmctiernan.com](https://www.bmctiernan.com) | lavender welcome page |
| [report.bmctiernan.com](https://report.bmctiernan.com) | blue lab report: request path, dns, verification, dashboard, controlled failure, backup plan |

## how it works

a visitor's browser asks dns for the name, dns points it at the droplet, and traefik (a reverse proxy) handles https and reads the hostname to pick the right container. each site is its own apache container serving one `index.html`.

the server is set up with my instructor's [373_hosting](https://github.com/kaw393939/373_hosting) scripts. this repo holds only my own work: the pages in `sites/`.

## what's in here

```
sites/
  bmctiernan.com/index.html
  www.bmctiernan.com/index.html
  report.bmctiernan.com/index.html (+ dashboard.png, failure-404.png)
hosting.example.json   template of the settings file (the real one stays private)
```

## deploying a page change

on the server, each page lives at `~/373_hosting/runtime/sites/<hostname>/index.html`. copy an edited page there and refresh the site; no restart needed.

## never committed

`acme.json` (certificates and the let's encrypt account key), the real `hosting.json`, ssh keys and passwords. `.gitignore` blocks the common ones.
