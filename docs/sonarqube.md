# SonarQube — what runs here, and the half that lives in the app repo

Static analysis and the quality gate for `tutac/revealroll`. Self-hosted in this cluster
rather than SonarCloud — the reasoning, and what was traded away, is decision 014.

| | |
|---|---|
| URL | `https://sonarqube.stg.revealroll.com` |
| Edition | Community Build (chart `2026.4.1`) |
| Database | `platform/sonarqube-db/` — one StatefulSet, official `postgres:17.6-alpine` |
| Owner layer | Argo CD, except the host sysctl, which is Ansible's |
| Runbook | `docs/runbooks/sonarqube-down.md` |

## Install order

Nothing here is reorderable; each step consumes the previous one.

```bash
# 1. Host prerequisite — vm.max_map_count. Without it Elasticsearch will not boot.
cd ansible && ansible-playbook -i inventory/staging.yml site.yml
ssh deploy@<node-ip> sysctl vm.max_map_count       # expect 524288

# 2. Credentials — sealed before anything that reads them exists
./scripts/seal-sonarqube.sh                        # writes secrets/sonarqube/

# 3. Commit. That is the deploy.
git add . && git commit && git push
```

Argo CD then syncs three Applications in wave order: `sonarqube-secrets` (-2),
`sonarqube-db` (-1), `sonarqube` (0). First boot takes several minutes — schema migration
followed by Elasticsearch index creation — and one failed sync retry in that window is
expected, not a problem to debug.

## First login

`admin` / `admin`, which SonarQube immediately forces you to change. **Put the new
password in the password manager**: nothing in this repository can recover it, deliberately
(the chart's password-setting Job re-runs on every sync and fails 401 forever once the
password is no longer the default, which shows up as a permanently Degraded Application).

Then, in the UI: **Administration → Security → Users → Tokens**, generate a *Global
Analysis Token*. That token goes into the **application** repo, not this one.

## The half that lives in `tutac/revealroll`

The scanner runs in the app repo's CI. Two files.

`sonar-project.properties` at the repo root:

```properties
sonar.projectKey=tutac_revealroll
sonar.sources=.
sonar.exclusions=**/node_modules/**,**/.next/**,**/*.test.ts,**/*.test.tsx,**/e2e/**
sonar.javascript.lcov.reportPaths=coverage/lcov.info
```

And a job in `.github/workflows/ci.yml`, gated on the existing checks and gating the image
build in turn:

```yaml
  sonar:
    needs: [static]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0          # blame data; a shallow clone makes "new code" wrong
      - uses: SonarSource/sonarqube-scan-action@v5
        env:
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
          SONAR_HOST_URL: ${{ vars.SONAR_HOST_URL }}
      - uses: SonarSource/sonarqube-quality-gate-action@v1
        timeout-minutes: 5
        env:
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
```

Then make the image build depend on it:

```yaml
  docker:
    needs: [static, ui, sonar]     # was [static, ui]
```

That last line is the whole point. Without it you have a report nobody is obliged to read;
with it, code that fails the gate cannot become an image, and therefore cannot become a
tag bump, and therefore cannot reach the cluster.

Note the direction of travel for credentials: the scanner token is a **CI** credential and
lives in GitHub secrets. It is not sealed into this repo, because nothing in the cluster
needs it. The cluster's credentials go the other way — sealed here, never in CI.

## The limitation to know before someone asks

**Community Build analyses one branch.** Pull-request decoration and branch analysis are
Developer Edition features. So this gate protects `main`; it does not annotate individual
pull requests. The options, honestly: accept main-only analysis (what we do), add the
third-party community branch plugin, or pay for Developer Edition.

## Why it is reachable from the internet

GitHub-hosted runners have to reach it, and IP-allowlisting the ingress against GitHub's
runner ranges is not practical. Compensating controls: `sonar.forceAuthentication`, a
strong admin password, and the fact that this instance holds staging code that is already
in a public repository. The better answer in an environment that matters is a self-hosted
runner inside the network, which removes the need to expose it at all.
