# Creates the DB credentials Secret in each environment namespace from cluster\.env (gitignored).
# The chart only references this Secret by name, so no credentials ever enter this public repo.
$ErrorActionPreference = "Stop"
$envFile = Join-Path $PSScriptRoot ".env"
if (-not (Test-Path $envFile)) {
    throw "Missing $envFile. Copy cluster\.env.example to cluster\.env and set real values."
}

$vars = @{}
Get-Content $envFile | Where-Object { $_ -match '^\s*[^#\s][^=]*=' } | ForEach-Object {
    $k, $v = $_ -split '=', 2
    $vars[$k.Trim()] = $v.Trim()
}
foreach ($k in "MYSQL_ROOT_PASSWORD", "MYSQL_USER", "MYSQL_PASSWORD") {
    if (-not $vars[$k]) { throw "$k is not set in $envFile" }
}

foreach ($ns in "homefinance-dev", "homefinance-prod") {
    kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
    kubectl -n $ns create secret generic homefinance-db `
        --from-literal=mysql-root-password=$($vars["MYSQL_ROOT_PASSWORD"]) `
        --from-literal=mysql-user=$($vars["MYSQL_USER"]) `
        --from-literal=mysql-password=$($vars["MYSQL_PASSWORD"]) `
        --dry-run=client -o yaml | kubectl apply -f -
}
Write-Host "Secret homefinance-db applied to homefinance-dev and homefinance-prod."
