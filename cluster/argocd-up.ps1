# Installs Argo CD and registers the dev and prod Applications. Safe to re-run.
# Requires: the cluster from minikube-up.ps1, helm and kubectl on PATH.
$chartVersion = "10.17.2"   # argo/argo-cd chart (Argo CD v3.6.1)
$root = Split-Path -Parent $PSScriptRoot

# Native commands are judged by exit code (see minikube-up.ps1 for why)
function Invoke-Native {
    param([string]$What, [scriptblock]$Command)
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "$What failed with exit code $LASTEXITCODE" }
}

Invoke-Native "helm repo add" { helm repo add argo https://argoproj.github.io/argo-helm --force-update }
Invoke-Native "helm repo update" { helm repo update }
Invoke-Native "install argo-cd" {
    helm upgrade --install argocd argo/argo-cd --version $chartVersion `
        --namespace argocd --create-namespace `
        -f "$root\cluster\argocd-values.yaml" --wait --timeout 10m
}

# The Applications adopt the existing Helm-installed releases in place (releaseName: homefinance)
Invoke-Native "apply Applications" { kubectl apply -f "$root\argocd" }

Write-Host ""
Write-Host "Argo CD is installed. UI:   kubectl -n argocd port-forward svc/argocd-server 8080:80   then http://localhost:8080"
Write-Host "Admin password:             kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}'  (base64-decode it)"
