# homefinance-gitops

Kubernetes deployment config for the [home finance app](https://github.com/0x4147/homefinance-app): a Helm chart plus per-environment values and local cluster setup. Phase 3 will have Argo CD watch this repo's `main` branch and deploy whatever is committed.

```
charts/homefinance/   Helm chart: backend, frontend, MySQL StatefulSet, ingress, network policies
envs/dev|prod/        Per-environment values (image tags, replicas, hostnames)
cluster/              Local minikube cluster, ingress-nginx values, secrets bootstrap
docs/exercises.md     Hands-on exercises (rolling update, node failure, network policy ...)
```

Environments are folders, not branches. Changes go in by pull request to `main`.

## Local cluster quick start (Windows, PowerShell)

Prerequisites: Docker Desktop (about 8 GB free), minikube, kubectl, helm.

```powershell
# 1. 3-node cluster with Calico + ingress-nginx
.\cluster\minikube-up.ps1

# 2. DB credentials (never committed)
Copy-Item cluster\.env.example cluster\.env      # then edit the passwords
.\cluster\bootstrap-secrets.ps1

# 3. Deploy an environment (set real image tags in envs/<env>/values.yaml first)
helm upgrade --install homefinance charts/homefinance -n homefinance-dev -f envs/dev/values.yaml

# 4. Reach it: add these to C:\Windows\System32\drivers\etc\hosts (as Administrator)
#      127.0.0.1 dev.homefinance.local prod.homefinance.local
#    and keep this running in an elevated terminal:
minikube -p homefinance tunnel
#    then open http://dev.homefinance.local
```

## Notes
- **Secrets:** the chart references the Secret `homefinance-db` by name and never creates it, so this repo can be public. Sealed Secrets is the planned replacement for the bootstrap script.
- **Images:** `ghcr.io/0x4147/homefinance-{backend,frontend}:<sha-tag>`, built and pushed by the app repo's `publish` workflow. Image tags are required values; there is no `latest`.
- **Service names** `backend`, `frontend` and `mysql` are fixed: the frontend image proxies `/api` to the host `backend`.
- **Network policies** are ingress-only for now and need a CNI that enforces them (Calico here).
