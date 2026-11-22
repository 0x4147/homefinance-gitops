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

## GitOps with Argo CD

Argo CD runs in the cluster (`argocd` namespace) and deploys whatever is on this repo's `main` branch. Nothing needs to reach the cluster from outside.

```
argocd/dev.yaml      Application for homefinance-dev: automated sync (prune + self-heal)
argocd/prod.yaml     Application for homefinance-prod: manual sync (a human clicks Sync after a promotion)
cluster/argocd-up.ps1, cluster/argocd-values.yaml   install (pinned chart version) and settings
.github/workflows/promote.yml   manual "Promote to prod" workflow that opens a PR
```

```powershell
.\cluster\argocd-up.ps1                                    # install Argo CD and register both Applications
kubectl -n argocd port-forward svc/argocd-server 8080:80   # UI at http://localhost:8080 (user: admin)
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}'   # base64-decode
```

**Flow.** A merge to `develop` in the app repo publishes `sha-xxxxxxx` images and a bot opens a PR here that bumps `envs/dev/values.yaml`; when the `helm` check passes it auto-merges and Argo CD rolls dev. To release to prod, run the **Promote to prod** workflow with a tag that has been verified in dev, merge the PR it opens, then Sync `homefinance-prod`. Rolling back is `git revert` of the bump commit.

**Needs the secret `GITOPS_PAT`** (fine-grained token for this repo: Contents and Pull requests read/write) so the PRs the workflows open can trigger the required `helm` check.

**Heads up:** dev self-heals, so manual `kubectl scale/edit` experiments in `homefinance-dev` are reverted within about a minute. Pause with `kubectl -n argocd patch app homefinance-dev --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'` (and re-apply `argocd/dev.yaml` to resume).
