# social-media-host

Static file server with one job: give the `social-poster` script (in the `Reveal-Social-Posts`
repo) a public `https://` URL, because Instagram and Facebook's publishing APIs only accept a
link to fetch — never a direct file upload.

Deliberately not part of the `revealroll` app itself — separate chart, separate namespace,
separate (tiny) resource footprint, so it can't affect the real app's deploys or rollbacks.

## One-time node setup

This chart uses a `hostPath` volume rather than a PVC — reasonable only because this is a
single-node cluster. The directory has to exist before the pod can mount it:

```
ssh deploy@<node> 'sudo mkdir -p /srv/social-media-host && sudo chown deploy:deploy /srv/social-media-host'
```

The `social-media-host` namespace also has to exist before the first sync: the `apps`
project's `clusterResourceWhitelist` is intentionally empty, so `CreateNamespace=true`
isn't an option here (same reason `revealroll`'s namespace isn't ArgoCD-managed either):

```
ssh deploy@<node> 'sudo k3s kubectl create namespace social-media-host'
```

(Both already done on `staging-1` as of 2026-10-07.)

## Publishing a file

The scheduler (or you, for a manual test) just copies the video onto the node — no `kubectl`
needed:

```
scp -i ~/.ssh/id_ed25519 my-reel.mp4 deploy@<node-ip>:/srv/social-media-host/
```

It's then live at `https://media.stg.revealroll.com/my-reel.mp4` within a few seconds — no
redeploy, no cache to bust.

## Cleanup

Files aren't deleted automatically by this chart. `run_queue.py` in `social-poster/` removes a
file a few days after its post goes live; for a one-off manual test, delete it by hand the same
way you uploaded it.
