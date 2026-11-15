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

---

# Results from the first run (minikube, 3 nodes, Calico)

What actually happened, so the exercises have a baseline to compare against.

| # | Exercise | Result |
|---|---|---|
| 1 | Zero-downtime rolling update (prod backend, `rollout restart`) | 204 requests through the ingress during the rollout, all HTTP 200 |
| 2 | Kill a pod | Replacement scheduled immediately; the other replica served traffic |
| 3 | Lose a node (`minikube node stop homefinance-m03`) | See timeline below |
| 4 | Network policy | A stray pod could not reach `mysql:3306` or `backend:8585`; the frontend could reach the backend |
| 5 | OOM | A pod with a 32Mi limit running `tail /dev/zero` ended `OOMKilled`, exit code 137 |
| 7 | PodDisruptionBudget | Evicting both prod backends back to back: first allowed, second refused with `Cannot evict pod as it would violate the pod's disruption budget`, allowed once the replacement was Ready |

## Exercise 3 timeline (node stopped at t=0)
- ~40-60s: node marked `NotReady`. Pods on it still show `Running`: nothing is evicted yet.
- ~300s after that: pods are evicted (the default `tolerationSeconds: 300` for `node.kubernetes.io/unreachable`). The replacements for the single-replica **dev** backend were created and the old pod sat in `Terminating` on the dead node.
- ~400s: the replacement was Ready and dev answered again. **Dev was down for about 5.5 minutes** because it runs one replica; **prod stayed up** (HTTP 200 throughout) because every prod component had a second replica on another node.
- When the node came back, pods did **not** move back: Kubernetes never rebalances running pods. Use the descheduler or a rollout if you want to spread them again.

## Storage lesson: hostPath volumes are tied to a node's disk, silently
minikube's default `standard` StorageClass uses `hostPath` (`/tmp/hostpath-provisioner/<ns>/<pvc>` on the node), and the PersistentVolume has **no node affinity**. We wrote a marker table in prod's MySQL, cordoned the node it ran on, and deleted the pod:

- the pod was rescheduled onto a different node and became Ready,
- the PVC still said `Bound`,
- the database was **empty** (0 tables): the new node's directory was fresh, while the real data stayed on the old node's disk.

Putting the pod back on the original node brought the marker table back. In a real cluster this would be silent data loss, which is why databases need replicated or network storage (CSI drivers, EBS, Longhorn, ...) or a managed service. Draining the node that hosts `mysql-0` is therefore **not** safe in this setup; the drain exercise should target a node without a database.

## Practical notes
- Ingress through `minikube tunnel` needs an elevated terminal; for quick checks use `kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 8088:80` and send `Host: dev.homefinance.local`.
- `kubectl create --raw ... -f -` did not send the Eviction body correctly on kubectl 1.32; going through `kubectl proxy` with `curl` worked.
- After the machine has been off for a while, `minikube start -p homefinance` takes about two minutes to settle; some pods restart while Calico comes up. Data in the volumes survives.
