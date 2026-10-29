# Creates the local 3-node cluster and installs the ingress controller. Safe to re-run.
# Requires: Docker Desktop running, minikube, kubectl, helm on PATH.
$ErrorActionPreference = "Stop"
$profileName = "homefinance"
$root = Split-Path -Parent $PSScriptRoot

# Calico because minikube's default CNI does not enforce NetworkPolicies
minikube start -p $profileName --nodes 3 --driver=docker --cni=calico --cpus=2 --memory=2560
kubectl config use-context $profileName

kubectl get nodes

foreach ($ns in "homefinance-dev", "homefinance-prod") {
    kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
}

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx `
    --namespace ingress-nginx --create-namespace `
    -f "$root\cluster\ingress-nginx-values.yaml" --wait

Write-Host "Cluster ready. Next: cluster\bootstrap-secrets.ps1, then helm upgrade --install (see README)."
