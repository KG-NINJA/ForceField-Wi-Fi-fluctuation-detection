param(
    [string]$Target = "AUTO_GATEWAY",
    [string]$Url = "ws://localhost:8080",
    [int]$WindowSize = 40,
    [int]$IntervalMs = 40
)

if (-not ([type]::GetType("System.Net.WebSockets.ClientWebSocket", $false))) {
    foreach ($assemblyName in @("System.Net.WebSockets.Client", "System.Net.Http", "System")) {
        try {
            Add-Type -AssemblyName $assemblyName -ErrorAction Stop
            break
        } catch {
        }
    }
}

function Get-LatencyMs {
    param([string]$PingTarget)

    $latency = $null
    try {
        $result = Test-Connection -TargetName $PingTarget -Count 1 -ErrorAction Stop
        if ($result | Get-Member -Name ResponseTime -ErrorAction SilentlyContinue) {
            $latency = [double]$result.ResponseTime
        } elseif ($result | Get-Member -Name Latency -ErrorAction SilentlyContinue) {
            $latency = [double]$result.Latency
        }
    } catch {
        $latency = $null
    }

    if ($null -eq $latency) {
        try {
            $pingText = & ping.exe -n 1 -w 300 $PingTarget 2>$null
            if ($LASTEXITCODE -eq 0) {
                $matched = $pingText | Select-String -Pattern '(?:time|時間)\s*[=<]?\s*(\d+)\s*ms' -AllMatches
                if ($matched -and $matched.Matches.Count -gt 0) {
                    $latency = [double]$matched.Matches[0].Groups[1].Value
                } elseif (($pingText -join " ") -match '(?:time|時間)\s*<\s*1\s*ms') {
                    $latency = 0.5
                }
            }
        } catch {
        }
    }

    if ($null -eq $latency) {
        return $null
    }

    return [math]::Max(0, [math]::Round($latency, 2))
}

function Get-TcpConnectLatencyMs {
    param(
        [string]$HostName,
        [int]$Port = 80
    )

    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $async = $client.BeginConnect($HostName, $Port, $null, $null)
        $ok = $async.AsyncWaitHandle.WaitOne(300)
        if (-not $ok) {
            $client.Close()
            return $null
        }
        $client.EndConnect($async)
        $sw.Stop()
        $client.Close()
        return [math]::Max(0, [math]::Round($sw.Elapsed.TotalMilliseconds, 2))
    } catch {
        return $null
    }
}

function Get-DefaultGatewayIp {
    try {
        $route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction Stop |
            Sort-Object -Property RouteMetric |
            Select-Object -First 1
        if ($route -and $route.NextHop -and $route.NextHop -ne "0.0.0.0") {
            return [string]$route.NextHop
        }
    } catch {
    }

    try {
        $routePrint = route print -4
        foreach ($line in $routePrint) {
            if ($line -match '^\s*0\.0\.0\.0\s+0\.0\.0\.0\s+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\s+') {
                return $matches[1]
            }
        }
    } catch {
    }

    try {
        $ipconfigText = ipconfig
        foreach ($line in $ipconfigText) {
            if ($line -match "(?:Default Gateway|デフォルト ゲートウェイ)[ .:]+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)") {
                return $matches[1]
            }
        }
    } catch {
    }

    return $null
}

function New-WebSocketConnection {
    param(
        [string[]]$Endpoints
    )

    if (-not ("System.Net.WebSockets.ClientWebSocket" -as [type])) {
        throw "ClientWebSocket type is unavailable in this PowerShell runtime."
    }

    foreach ($endpoint in $Endpoints) {
        $socket = [System.Net.WebSockets.ClientWebSocket]::new()
        try {
            $uri = [Uri]::new($endpoint)
            [void]$socket.ConnectAsync($uri, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
            return @{
                Socket = $socket
                Endpoint = $endpoint
            }
        } catch {
            try {
                $socket.Dispose()
            } catch {
            }
        }
    }

    throw ("Unable to connect to any endpoint: {0}" -f ($Endpoints -join ", "))
}

function Send-JsonPayload {
    param(
        [System.Net.WebSockets.ClientWebSocket]$Socket,
        [string]$Json
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Json)
    $segment = [System.ArraySegment[byte]]::new($bytes)

    [void]$Socket.SendAsync(
        $segment,
        [System.Net.WebSockets.WebSocketMessageType]::Text,
        $true,
        [System.Threading.CancellationToken]::None
    ).GetAwaiter().GetResult()
}

$samples = [System.Collections.Generic.Queue[double]]::new()
$score = 0.0
$failedProbeCount = 0
$urlUri = [Uri]::new($Url)
$defaultGateway = Get-DefaultGatewayIp
$fallbackHost = $urlUri.Host
$fallbackPort = if ($urlUri.Port -gt 0) { $urlUri.Port } else { 80 }
$wsPort = if ($urlUri.Port -gt 0) { $urlUri.Port } else { 80 }
$wsScheme = $urlUri.Scheme

$endpointCandidates = [System.Collections.Generic.List[string]]::new()
[void]$endpointCandidates.Add(("{0}://{1}:{2}" -f $wsScheme, $urlUri.Host, $wsPort))
if ($urlUri.Host -eq "localhost") {
    [void]$endpointCandidates.Add(("{0}://127.0.0.1:{1}" -f $wsScheme, $wsPort))
} elseif ($urlUri.Host -eq "127.0.0.1") {
    [void]$endpointCandidates.Add(("{0}://localhost:{1}" -f $wsScheme, $wsPort))
}

if (($Target -eq "AUTO_GATEWAY" -or [string]::IsNullOrWhiteSpace($Target)) -and $defaultGateway) {
    $Target = $defaultGateway
    Write-Host "Using default gateway target: $Target"
}

while ($true) {
    $socket = $null
    try {
        $connection = New-WebSocketConnection -Endpoints $endpointCandidates.ToArray()
        $socket = $connection.Socket
        Write-Host ("Connected to {0}" -f $connection.Endpoint)

        while ($socket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            $loopStart = Get-Date
            $latency = Get-LatencyMs -PingTarget $Target
            if ($null -eq $latency) {
                $latency = Get-TcpConnectLatencyMs -HostName $fallbackHost -Port $fallbackPort
            }
            if ($null -eq $latency) {
                $failedProbeCount += 1
                if ($defaultGateway -and $Target -ne $defaultGateway -and $failedProbeCount -ge 20) {
                    $Target = $defaultGateway
                    $failedProbeCount = 0
                    Write-Warning ("Switching target to default gateway: {0}" -f $Target)
                }
                Write-Warning ("Latency probe failed for target {0} and fallback {1}:{2}" -f $Target, $fallbackHost, $fallbackPort)
                Start-Sleep -Milliseconds $IntervalMs
                continue
            }
            $failedProbeCount = 0

            $samples.Enqueue($latency)
            while ($samples.Count -gt $WindowSize) {
                [void]$samples.Dequeue()
            }

            $sum = 0.0
            foreach ($value in $samples) {
                $sum += $value
            }

            $average = if ($samples.Count -gt 0) { $sum / $samples.Count } else { $latency }
            $diff = $latency - $average

            $varianceSum = 0.0
            foreach ($value in $samples) {
                $distance = $value - $average
                $varianceSum += ($distance * $distance)
            }
            $stdDev = [math]::Sqrt($varianceSum / [math]::Max(1, $samples.Count))

            $normalizedDiff = [math]::Min(1.0, [math]::Abs($diff) / 2.0)
            $normalizedStd = [math]::Min(1.0, $stdDev / 2.0)
            $micro = [math]::Min(1.0, ($normalizedDiff * 0.7) + ($normalizedStd * 0.3))

            $targetScore = $micro * 20.0
            $score = ($score * 0.9) + ($targetScore * 0.1)

            if ($score -lt 0) { $score = 0 }
            if ($score -gt 20) { $score = 20 }

            $payload = @{
                score = [math]::Round($score, 2)
                latency = [math]::Round($latency, 2)
                micro = [math]::Round($micro, 3)
            } | ConvertTo-Json -Compress

            Send-JsonPayload -Socket $socket -Json $payload
            Write-Host ("Latency {0} Score {1} Micro {2}" -f [math]::Round($latency, 2), [math]::Round($score, 2), [math]::Round($micro, 3))

            $elapsedMs = ((Get-Date) - $loopStart).TotalMilliseconds
            $sleepMs = [int][math]::Floor($IntervalMs - $elapsedMs)
            if ($sleepMs -gt 0) {
                Start-Sleep -Milliseconds $sleepMs
            }
        }
    } catch {
        Write-Warning ("Socket loop error: {0}" -f $_.Exception.Message)
        Start-Sleep -Milliseconds 500
    } finally {
        if ($socket -ne $null) {
            try {
                $socket.Dispose()
            } catch {
            }
        }
    }
}
