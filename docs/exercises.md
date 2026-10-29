# Exercises

Run these against `homefinance-prod` (2 replicas) once it is deployed. Each says what you should observe and why it matters.

## 1. Zero-downtime rolling update
```powershell
# terminal A: hammer the app, print status codes
while ($true) { (Invoke-WebRequest http://prod.homefinance.local/api/v1/trip -UseBasicParsing).StatusCode; Start-Sleep -Milliseconds 300 }
# terminal B: change a backend tag in envs/prod/values.yaml, then
helm upgrade homefinance charts/homefinance -n homefinance-prod -f envs/prod/values.yaml
kubectl -n homefinance-prod rollout status deploy/backend
```
Expect: only 200s. `maxUnavailable: 0` plus the readiness probe means a new pod must be Ready before an old one is removed.

## 2. Kill a pod
`kubectl -n homefinance-prod delete pod -l app.kubernetes.io/component=backend --wait=false`, keep the loop running. Expect: a replacement starts immediately and traffic keeps flowing through the other replica.

## 3. Lose a node
`minikube -p homefinance node stop homefinance-m03`, then `kubectl get pods -n homefinance-prod -o wide -w`. Expect: pods from that node are rescheduled after the node is marked NotReady (about 5 minutes by default; look up `tolerationSeconds`). If MySQL lived on that node it will **not** move: its volume is node-local. That is why databases need replicated storage or a managed service.

## 4. Prove the network policy
```powershell
# from a throwaway pod (not the backend): connection to MySQL should hang / time out
kubectl -n homefinance-prod run probe --rm -it --image=busybox:1.36 --restart=Never -- nc -zv -w 3 mysql 3306
# from the backend it works
kubectl -n homefinance-prod exec deploy/backend -- sh -c "wget -qO- -T 3 http://localhost:8585/actuator/health/readiness"
```
Delete the `mysql-from-backend` policy, repeat the probe, and watch it connect. Restore with `helm upgrade`.

## 5. Resource limits and OOM
Lower `backend.resources.limits.memory` to `256Mi` in a scratch values file, deploy, and watch `kubectl describe pod` show `OOMKilled`, then restore it.

## 6. Side-by-side environments
Compare `kubectl get all -n homefinance-dev` and `-n homefinance-prod`: same chart, different replicas, PDB and hostnames from the values files only.

## 7. PodDisruptionBudget
`kubectl drain homefinance-m02 --ignore-daemonsets --delete-emptydir-data` with the prod PDB in place: the drain evicts backend pods one at a time and never leaves fewer than one running.
