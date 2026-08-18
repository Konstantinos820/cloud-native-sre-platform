param(
    [string]$Namespace = "sre-platform",
    [string]$PostgresPod = "sre-platform-app-postgres-0",
    [string]$FastApiDeployment = "sre-platform-app-fastapi",
    [string]$KindNode = "kind-control-plane",
    [string]$ApiUrl = "http://localhost:8000/users",
    [int]$Samples = 5,
    [int]$ReadinessTimeoutSeconds = 30,
    [int]$RecoveryTimeoutSeconds = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$pgPid = $null
$apiPodIps = @()
$rulesAdded = @()


function Invoke-RequestSamples {
    param(
        [string]$Stage,
        [int]$Count
    )

    Write-Host ""
    Write-Host "=== $Stage ==="

    $results = 1..$Count | ForEach-Object {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            Invoke-RestMethod $ApiUrl -TimeoutSec 10 | Out-Null
            $result = "SUCCESS"
            $errorMessage = ""
        }
        catch {
            $result = "FAILED"
            $errorMessage = $_.Exception.Message
        }

        $sw.Stop()

        [PSCustomObject]@{
            Run          = $_
            Result       = $result
            Milliseconds = [math]::Round($sw.Elapsed.TotalMilliseconds, 2)
            Error        = $errorMessage
        }
    }

    $results | Format-Table -AutoSize | Out-Host

    return $results
}


function Remove-OutageRules {
    if (-not $pgPid) {
        return
    }

    foreach ($ip in @($rulesAdded)) {
        docker exec $KindNode `
            nsenter -t $pgPid -n `
            iptables -D INPUT `
            -p tcp `
            -s $ip `
            --dport 5432 `
            -j REJECT `
            --reject-with tcp-reset `
            2>$null
    }

    $script:rulesAdded = @()
}


function Get-ReadyReplicaCount {
    $value = kubectl get deployment $FastApiDeployment `
        -n $Namespace `
        -o jsonpath="{.status.readyReplicas}"

    if ([string]::IsNullOrWhiteSpace($value)) {
        return 0
    }

    return [int]$value
}


Write-Host "============================================"
Write-Host " PostgreSQL Dependency Outage Experiment"
Write-Host "============================================"
Write-Host ""
Write-Host "Namespace: $Namespace"
Write-Host "PostgreSQL pod: $PostgresPod"
Write-Host "FastAPI deployment: $FastApiDeployment"
Write-Host "Target API: $ApiUrl"


try {
    # ------------------------------------------------------------
    # Pre-flight
    # ------------------------------------------------------------

    Write-Host ""
    Write-Host "[1/7] Checking prerequisites..."

    Get-Command kubectl -ErrorAction Stop | Out-Null
    Get-Command docker -ErrorAction Stop | Out-Null

    $pgContainer = kubectl get pod $PostgresPod `
        -n $Namespace `
        -o jsonpath="{.status.containerStatuses[0].containerID}"

    if (-not $pgContainer) {
        throw "Could not determine PostgreSQL container ID."
    }

    if ($pgContainer -notlike "containerd://*") {
        throw "Expected containerd runtime but found: $pgContainer"
    }

    $pgContainerId = $pgContainer -replace "^containerd://", ""

    $inspectJson = docker exec $KindNode crictl inspect $pgContainerId

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to inspect PostgreSQL container."
    }

    $inspect = $inspectJson | ConvertFrom-Json
    $pgPid = $inspect.info.pid

    if (-not $pgPid) {
        throw "Could not determine PostgreSQL container PID."
    }

    Write-Host "PostgreSQL PID: $pgPid"


    # ------------------------------------------------------------
    # Discover FastAPI pod IPs
    # ------------------------------------------------------------

    Write-Host ""
    Write-Host "[2/7] Discovering FastAPI pod IPs..."

    $podData = kubectl get pods `
        -n $Namespace `
        -o json |
        ConvertFrom-Json

    $apiPodIps = @(
        $podData.items |
            Where-Object {
                $_.metadata.name -like "$FastApiDeployment-*"
            } |
            ForEach-Object {
                $_.status.podIP
            } |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_)
            }
    )

    if ($apiPodIps.Count -eq 0) {
        throw "No FastAPI pod IPs were discovered."
    }

    Write-Host "FastAPI pod IPs:"
    $apiPodIps | ForEach-Object {
        Write-Host " - $_"
    }


    # ------------------------------------------------------------
    # Ensure no stale outage rules already exist
    # ------------------------------------------------------------

    Write-Host ""
    Write-Host "[3/7] Checking for stale PostgreSQL outage rules..."

    $existingRules = docker exec $KindNode `
        nsenter -t $pgPid -n `
        iptables -L INPUT -n --line-numbers

    foreach ($ip in $apiPodIps) {
        if (
            $existingRules -match [regex]::Escape($ip) -and
            $existingRules -match "5432"
        ) {
            throw "Existing PostgreSQL outage rule detected for $ip. Refusing to continue."
        }
    }

    Write-Host "No stale outage rules detected."


    # ------------------------------------------------------------
    # Warm-up / baseline availability
    # ------------------------------------------------------------

    Write-Host ""
    Write-Host "[4/7] Checking normal application availability..."

    try {
        Invoke-RestMethod $ApiUrl -TimeoutSec 10 | Out-Null
    }
    catch {
        throw @"
FastAPI is not reachable at $ApiUrl.

Start a port-forward in another terminal:

kubectl port-forward -n $Namespace service/sre-platform-app-fastapi 8000:80
"@
    }

    Write-Host "Baseline request successful."


    # ------------------------------------------------------------
    # Inject outage
    # ------------------------------------------------------------

    Write-Host ""
    Write-Host "[5/7] Blocking FastAPI -> PostgreSQL TCP/5432..."

    foreach ($ip in $apiPodIps) {
        docker exec $KindNode `
            nsenter -t $pgPid -n `
            iptables -I INPUT 1 `
            -p tcp `
            -s $ip `
            --dport 5432 `
            -j REJECT `
            --reject-with tcp-reset

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to add outage rule for FastAPI pod IP $ip."
        }

        $rulesAdded += $ip
    }


    Write-Host ""
    Write-Host "Active PostgreSQL outage rules:"

    docker exec $KindNode `
        nsenter -t $pgPid -n `
        iptables -L INPUT -n --line-numbers


    # ------------------------------------------------------------
    # Observe application failure
    # ------------------------------------------------------------

    Write-Host ""
    Write-Host "[6/7] Measuring outage behavior..."

    $outageResults = Invoke-RequestSamples `
        -Stage "OUTAGE" `
        -Count $Samples

    $failedCount = @(
        $outageResults |
            Where-Object { $_.Result -eq "FAILED" }
    ).Count

    Write-Host "Failed requests during outage: $failedCount/$Samples"


    # Wait for readiness to react.
    Write-Host ""
    Write-Host "Waiting for FastAPI readiness to react..."

    $deadline = (Get-Date).AddSeconds($ReadinessTimeoutSeconds)
    $readyReplicas = Get-ReadyReplicaCount

    while (
        $readyReplicas -gt 0 -and
        (Get-Date) -lt $deadline
    ) {
        Start-Sleep -Seconds 1
        $readyReplicas = Get-ReadyReplicaCount
    }

    Write-Host "Ready replicas during outage: $readyReplicas"

    kubectl get pods -n $Namespace | Out-Host
}
finally {
    # ------------------------------------------------------------
    # ALWAYS remove outage rules
    # ------------------------------------------------------------

    if ($rulesAdded.Count -gt 0 -and $pgPid) {
        Write-Host ""
        Write-Host "[CLEANUP] Removing PostgreSQL outage rules..."

        Remove-OutageRules

        Write-Host "PostgreSQL outage rules removed."
    }
}


# ------------------------------------------------------------
# Recovery verification
# ------------------------------------------------------------

Write-Host ""
Write-Host "[7/7] Waiting for FastAPI recovery..."

$deadline = (Get-Date).AddSeconds($RecoveryTimeoutSeconds)

do {
    $readyReplicas = Get-ReadyReplicaCount

    if ($readyReplicas -ge 2) {
        break
    }

    Start-Sleep -Seconds 1
}
while ((Get-Date) -lt $deadline)

Write-Host "Ready replicas after recovery: $readyReplicas"

if ($readyReplicas -lt 2) {
    throw "FastAPI did not recover to at least 2 ready replicas within the timeout."
}

# Give Kubernetes endpoints a brief stabilization period.
Start-Sleep -Seconds 2

Write-Host ""
Write-Host "Verifying recovery from inside the cluster..."

$podData = kubectl get pods -n $Namespace -o json | ConvertFrom-Json

$testPod = $podData.items |
    Where-Object {
        $_.metadata.name -like "$FastApiDeployment-*"
    } |
    Select-Object -First 1

if (-not $testPod) {
    throw "Could not find a FastAPI pod for recovery verification."
}

$testPodName = $testPod.metadata.name

$recoveryResults = 1..$Samples | ForEach-Object {
    $output = kubectl exec -n $Namespace $testPodName -- `
        python -c "import time, urllib.request; t=time.perf_counter(); r=urllib.request.urlopen('http://sre-platform-app-fastapi/users', timeout=5); print(f'{r.status} {((time.perf_counter()-t)*1000):.2f}')"

    if (
        $LASTEXITCODE -eq 0 -and
        $output -match "^200\s+([0-9.]+)$"
    ) {
        [PSCustomObject]@{
            Run          = $_
            Result       = "SUCCESS"
            Milliseconds = [double]$Matches[1]
        }
    }
    else {
        [PSCustomObject]@{
            Run          = $_
            Result       = "FAILED"
            Milliseconds = $null
        }
    }
}

$recoveryResults | Format-Table -AutoSize | Out-Host

$recoverySuccess = @(
    $recoveryResults |
        Where-Object { $_.Result -eq "SUCCESS" }
).Count

Write-Host "Successful in-cluster recovery requests: $recoverySuccess/$Samples"

if ($recoverySuccess -ne $Samples) {
    throw "Not all in-cluster recovery requests succeeded."
}


Write-Host ""
Write-Host "Final FastAPI state:"
kubectl get pods -n $Namespace | Out-Host

Write-Host ""
Write-Host "Final PostgreSQL INPUT rules:"
docker exec $KindNode `
    nsenter -t $pgPid -n `
    iptables -L INPUT -n --line-numbers |
    Out-Host


Write-Host ""
Write-Host "============================================"
Write-Host " Experiment finished"
Write-Host " Fault cleanup completed"
Write-Host " Service recovery verified"
Write-Host "============================================"