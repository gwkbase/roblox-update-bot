#Requires -Version 7.0
param(
    [ValidateRange(60, 86400)][int]$IntervalSeconds = 120,
    [switch]$DryRun,
    [switch]$Once
)

$ErrorActionPreference = 'Stop'
$liveUrl = 'https://clientsettingscdn.roblox.com/v2/client-version/WindowsPlayer'
$historyUrl = 'https://setup.rbxcdn.com/DeployHistory.txt'
$channel = $env:DISCORD_CHANNEL_ID
$token = $env:DISCORD_BOT_TOKEN
if (!$DryRun -and (!$token -or $channel -notmatch '^\d{17,20}$')) {
    throw 'Set DISCORD_BOT_TOKEN and DISCORD_CHANNEL_ID, or use -DryRun.'
}

$statePath = Join-Path $PSScriptRoot "state-$channel.json"
$state = @{ live = ''; upcoming = '' }
if (!$DryRun -and (Test-Path -LiteralPath $statePath)) {
    $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json -AsHashtable
}

function Send-Notice([string]$message, [string]$eventKey) {
    if ($DryRun) {
        Write-Host $message
        return
    }
    $hash = [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($eventKey))
    $body = @{
        content = $message
        allowed_mentions = @{ parse = @() }
        nonce = [Convert]::ToHexString($hash).Substring(0, 24)
        enforce_nonce = $true
    } | ConvertTo-Json -Compress -Depth 4
    Invoke-RestMethod -Uri "https://discord.com/api/v10/channels/$channel/messages" -Method Post `
        -UserAgent 'DiscordBot (https://github.com/gwkbase/roblox-update-bot, 1.0)' -Headers @{ Authorization = "Bot $token" } -ContentType 'application/json; charset=utf-8' `
        -Body $body -TimeoutSec 20 | Out-Null
}

function Save-State {
    if ($DryRun) { return }
    $temporary = "$statePath.tmp"
    $state | ConvertTo-Json -Compress | Set-Content -LiteralPath $temporary
    [IO.File]::Move($temporary, $statePath, $true)
}

do {
    $wait = $IntervalSeconds
    try {
        $stage = 'Roblox LIVE lookup'
        $live = Invoke-RestMethod -Uri $liveUrl -TimeoutSec 20
        if ($live.version -notmatch '^\d+\.\d+\.\d+\.\d+$' -or
            $live.clientVersionUpload -notmatch '^version-[0-9a-f]+$') {
            throw 'Unexpected Roblox LIVE response.'
        }
        $observed = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        if ($state.live -ne $live.clientVersionUpload) {
            $title = if ($state.live) { 'Roblox Windows Player updated' } else { 'Roblox Windows Player is live' }
            $stage = 'Discord LIVE alert'
            Send-Notice "**$title**`nBuild **$($live.version)** ($($live.clientVersionUpload))`nObserved <t:${observed}:F>." "live:$($state.live):$($live.clientVersionUpload)"
            $state.live = $live.clientVersionUpload
            Save-State
        }

        $stage = 'Roblox deployment history lookup'
        $history = (Invoke-WebRequest -Uri $historyUrl -TimeoutSec 20).Content
        $candidates = [regex]::Matches($history, '(?m)^New WindowsPlayer \S+ at [^\r`n]+?, file version:\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+),')
        $upcoming = $candidates | ForEach-Object {
            [version] (($_.Groups[1..4] | ForEach-Object Value) -join '.')
        } | Where-Object { $_ -gt [version]$live.version } | Sort-Object -Descending | Select-Object -First 1
        if ($upcoming -and (!$state.upcoming -or $upcoming -gt [version]$state.upcoming)) {
            $stage = 'Discord upcoming build alert'
            Send-Notice "**Newer Roblox Windows build spotted**`nBuild **$upcoming** appeared in public deployment history. LIVE is **$($live.version)**.`nObserved <t:${observed}:F>. Release timing is unconfirmed." "upcoming:$upcoming"
            $state.upcoming = $upcoming.ToString()
            Save-State
        }
    }
    catch {
        $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        if ($status -eq 429) {
            $retry = 0.0
            if ($_.ErrorDetails.Message) {
                try { $retry = [double](ConvertFrom-Json $_.ErrorDetails.Message).retry_after } catch {}
            }
            $wait = [Math]::Max($wait, [Math]::Ceiling($retry))
        }
        if ($status) {
            $code = $null
            try { $code = [int](ConvertFrom-Json $_.ErrorDetails.Message).code } catch {}
            $detail = if ($null -ne $code -and $stage -like 'Discord*') { ", Discord code $code" } else { '' }
            Write-Warning "$stage failed (HTTP $status$detail)."
        }
        else { Write-Warning "Poll failed: $($_.Exception.GetType().Name)." }
        if ($Once) { exit 1 }
    }
    if (!$Once) { Start-Sleep -Seconds $wait }
} while (!$Once)
