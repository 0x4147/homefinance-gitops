# Creates the local 3-node cluster and installs the ingress controller. Safe to re-run.
# Requires: Docker Desktop running, minikube, kubectl, helm on PATH.
$profileName = "homefinance"
$root = Split-Path -Parent $PSScriptRoot

# Windows PowerShell 5.1 turns any stderr output from a native command into a terminating error
# when $ErrorActionPreference is "Stop" (minikube prints harmless warnings there), so native
# commands are judged by their exit code instead.
function Invoke-Native {
    param([string]$What, [scriptblock]$Command)
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "$What failed with exit code $LASTEXITCODE" }
}

# Calico because minikube's default CNI does not enforce NetworkPolicies
Invoke-Native "minikube start" { minikube start -p $profileName --nodes 3 --driver=docker --cni=calico --cpus=2 --memory=2560 }
# --nodes only applies when a profile is first created, so top up a profile that has fewer
$nodeCount = (kubectl --context $profileName get nodes --no-headers | Measure-Object).Count
while ($nodeCount -lt 3) {
    Invoke-Native "minikube node add" { minikube node add -p $profileName }
    $nodeCount++
}
Invoke-Native "kubectl use-context" { kubectl config use-context $profileName }
Invoke-Native "kubectl get nodes" { kubectl get nodes }

foreach ($ns in "homefinance-dev", "homefinance-prod") {
    Invoke-Native "create namespace $ns" { kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f - }
}

Invoke-Native "helm repo add" { helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update }
Invoke-Native "helm repo update" { helm repo update }
Invoke-Native "install ingress-nginx" {
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx `
        --namespace ingress-nginx --create-namespace `
        -f "$root\cluster\ingress-nginx-values.yaml" --wait
}

Write-Host "Cluster ready. Next: cluster\bootstrap-secrets.ps1, then helm upgrade --install (see README)."
