param(
    [string]$Namespace = "sre-platform",
    [string]$PostgresPod = "sre-platform-app-postgres-0",
    [string]$KindNode = "kind-control-plane",
    [string]$ApiUrl = "http://localhost:8000/users",
    [int]$DelayMs = 300,
    [int]$Samples = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$chaosApplied = $false
$pgPid = $null
$networkInterface = $null


function Invoke-LatencySamples {
    param(
        [string]$Stage,
        [int]$Count
    )

    Write-Host ""
    Write-Host "=== $Stage ==="

    $results = 1..$Count | ForEach-Object {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            Invoke-RestMethod $ApiUrl -TimeoutSec 15 | Out-Null
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


function Get-LatencyStats {
    param(
        [string]$Stage,
        [array]$Results
    )

    $successful = @(
        $Results |
            Where-Object { $_.Result -eq "SUCCESS" } |
            Select-Object -ExpandProperty Milliseconds
    )

    if ($successful.Count -eq 0) {
        Write-Host "$Stage`: no successful requests."
        return
    }

    $sorted = @($successful | Sort-Object)

    $average = [math]::Round(
        ($successful | Measure-Object -Average).Average,
        2
    )

    if ($sorted.Count % 2 -eq 1) {
        $median = $sorted[[math]::Floor($sorted.Count / 2)]
    }
    else {
        $middle = $sorted.Count / 2
        $median = ($sorted[$middle - 1] + $sorted[$middle]) / 2
    }

    $median = [math]::Round($median, 2)

    Write-Host "$Stage average: $average ms"
    Write-Host "$Stage median : $median ms"
    Write-Host "$Stage success: $($successful.Count)/$($Results.Count)"
}


Write-Host "============================================"
Write-Host " PostgreSQL Network Latency Chaos Experiment"
Write-Host "============================================"
Write-Host ""
Write-Host "Delay: $DelayMs ms"
Write-Host "Samples per stage: $Samples"
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
    # Discover network interface
    # ------------------------------------------------------------

    Write-Host ""
    Write-Host "[2/7] Discovering PostgreSQL network interface..."

    $defaultRoute = docker exec $KindNode `
        nsenter -t $pgPid -n ip route show default

    if ($LASTEXITCODE -ne 0) {
        throw "Could not inspect PostgreSQL network namespace."
    }

    if ($defaultRoute -notmatch "\sdev\s+([^\s]+)") {
        throw "Could not determine PostgreSQL network interface."
    }

    $networkInterface = $Matches[1]

    Write-Host "Interface: $networkInterface"

    $existingQdisc = docker exec $KindNode `
        nsenter -t $pgPid -n tc qdisc show dev $networkInterface

    Write-Host "Current qdisc:"
    Write-Host $existingQdisc

    if ($existingQdisc -match "netem") {
        throw "Existing netem rule detected. Refusing to overwrite it."
    }


    # ------------------------------------------------------------
    # Check API / warm-up
    # ------------------------------------------------------------

    Write-Host ""
    Write-Host "[3/7] Checking API and warming up..."

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

    Write-Host "Warm-up request successful."


    # ------------------------------------------------------------
    # Baseline
    # ------------------------------------------------------------

    Write-Host ""
    Write-Host "[4/7] Measuring baseline..."

    $baseline = Invoke-LatencySamples `
        -Stage "BASELINE" `
        -Count $Samples

    Get-LatencyStats `
        -Stage "Baseline" `
        -Results $baseline


    # ------------------------------------------------------------
    # Fault injection
    # ------------------------------------------------------------

    Write-Host ""
    Write-Host "[5/7] Injecting $DelayMs ms PostgreSQL network latency..."

    docker exec $KindNode `
        nsenter -t $pgPid -n `
        tc qdisc replace dev $networkInterface root netem delay "${DelayMs}ms"

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to inject network latency."
    }

    $chaosApplied = $true

    $activeQdisc = docker exec $KindNode `
        nsenter -t $pgPid -n tc qdisc show dev $networkInterface

    Write-Host "Active qdisc:"
    Write-Host $activeQdisc

    if ($activeQdisc -notmatch "netem") {
        throw "netem rule was not detected after fault injection."
    }


    # ------------------------------------------------------------
    # Degraded measurements
    # ------------------------------------------------------------

    Write-Host ""
    Write-Host "[6/7] Measuring degraded behavior..."

    $degraded = Invoke-LatencySamples `
        -Stage "DEGRADED" `
        -Count $Samples

    Get-LatencyStats `
        -Stage "Degraded" `
        -Results $degraded
}
finally {
    # ------------------------------------------------------------
    # ALWAYS remove the fault
    # ------------------------------------------------------------

    if ($chaosApplied -and $pgPid -and $networkInterface) {
        Write-Host ""
        Write-Host "[CLEANUP] Removing network latency..."

        docker exec $KindNode `
            nsenter -t $pgPid -n `
            tc qdisc del dev $networkInterface root 2>$null

        $chaosApplied = $false

        Write-Host "Chaos rule removed."
    }
}


# ------------------------------------------------------------
# Recovery verification
# ------------------------------------------------------------

Write-Host ""
Write-Host "[7/7] Verifying recovery..."

Start-Sleep -Seconds 2

# Ignore one transient request immediately after cleanup.
try {
    Invoke-RestMethod $ApiUrl -TimeoutSec 10 | Out-Null
}
catch {
    Write-Warning "Recovery warm-up request failed: $($_.Exception.Message)"
}

$recovered = Invoke-LatencySamples `
    -Stage "RECOVERY" `
    -Count $Samples

Get-LatencyStats `
    -Stage "Recovery" `
    -Results $recovered


Write-Host ""
Write-Host "============================================"
Write-Host " Experiment finished"
Write-Host " Fault cleanup completed"
Write-Host "============================================"