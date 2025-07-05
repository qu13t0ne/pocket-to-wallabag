<#
  .SYNOPSIS
    Adds a 'FAVORITE' tag to all starred Pocket articles (both unread and archived).

  .DESCRIPTION
    This script connects to the Pocket API using your provided consumer key and access token.
    It retrieves up to 5000 starred (favorited) unread and archived items, filters out those
    already tagged with 'FAVORITE', and applies the tag in batches. Failed batches are logged
    for retry.

  .INPUTS
    None. The script fetches data directly from Pocket's API.

  .OUTPUTS
    Console logs, and optionally a failed batch file for retry.

  .EXAMPLE
    Run directly:
        $env:POCKET_CONSUMER_KEY = "your-key"
        $env:POCKET_ACCESS_TOKEN = "your-token"
        .\Update-PocketFavoritesWithTag.ps1

  .LINK
  https://github.com/qu13t0ne/pocket2wallabag

  .NOTES
  Author:         Mike Owens, mikeowens (at) fastmail (dot) com
  Website:        https://michaelowens.me
  GitLab:         https://gitlab.com/qu13t0ne
  GitHub:         https://github.com/qu13t0ne
  Bluesky:        https://bsky.app/profile/qu13t0ne.bsky.social
  Mastodon:       https://infosec.exchange/@qu13t0ne

  - Rate limit: 10,000 API calls per hour (enforced by Pocket).
  - Items are tagged in batches of 250, with retry and backoff logic for errors.
  - Failed batches are written to a file: failed_batches_<timestamp>.txt

  Prerequisites:
  - PowerShell 7.0+
  - Environment variables:
      $env:POCKET_CONSUMER_KEY
      $env:POCKET_ACCESS_TOKEN

#>

#region ----- CONFIG --------------------

$consumerKey = $env:POCKET_CONSUMER_KEY
$accessToken = $env:POCKET_ACCESS_TOKEN
$tagToAdd = "favorite"
$batchSize = 250
$maxCallsPerHour = 10000
$maxRetries = 3
$apiCallCount = 0
$successBatches = 0
$failedBatches = 0
$timestamp = Get-Date -Format "yyyy-MM-ddTHH-mm-ss"
$failedBatchFile = "failed_batches_$timestamp.txt"

#endregion ----- CONFIG --------------------

#region ----- FUNCTIONS --------------------

function Invoke-PocketApi {
    param (
        [string]$Url,
        [object]$Body
    )
    $jsonBody = $Body | ConvertTo-Json -Depth 10 -Compress
    return Invoke-RestMethod -Uri $Url -Method Post -ContentType "application/json; charset=UTF-8" -Body $jsonBody
}

#endregion ----- FUNCTIONS --------------------

#region ----- MAIN --------------------

# ----- GET FAVORITED ITEMS --------------------

Write-Host "Fetching unread favorited items..."
$responseUnread = Invoke-PocketApi -Url "https://getpocket.com/v3/get" -Body @{
    consumer_key = $consumerKey
    access_token = $accessToken
    favorite     = "1"
    state        = "unread"
    detailType   = "complete"
    count        = 5000
}
$apiCallCount++

Write-Host "Fetching archived favorited items..."
$responseArchive = Invoke-PocketApi -Url "https://getpocket.com/v3/get" -Body @{
    consumer_key = $consumerKey
    access_token = $accessToken
    favorite     = "1"
    state        = "archive"
    detailType   = "complete"
    count        = 5000
}
$apiCallCount++

# Properly extract item objects from both .list dictionaries
$unreadItems = @($responseUnread.list.psobject.Properties | ForEach-Object { $_.Value })
$archiveItems = @($responseArchive.list.psobject.Properties | ForEach-Object { $_.Value })

# Combine and filter
$allItems = $unreadItems + $archiveItems

$itemsToTag = $allItems | Where-Object { $null -eq $_.tags -or $tagToAdd -notin $_.tags }

Write-Host "Found $($itemsToTag.Count) items to tag..."

# ----- ADD TAG TO FAVORITED ITEMS --------------------

for ($i = 0; $i -lt $itemsToTag.Count; $i += $batchSize) {
    $remainingItems = $itemsToTag.Count - $i
    $remainingBatches = [Math]::Ceiling($remainingItems / $batchSize)
    $projectedCalls = $apiCallCount + $remainingBatches
    if ($projectedCalls -gt $maxCallsPerHour) {
        $nextReset = (Get-Date).AddHours(1).ToString("yyyy-MM-dd HH:mm:ss")
        Write-Host "Approaching rate limit. Sleeping until quota resets at $nextReset..."
        Start-Sleep -Seconds 3600
        $apiCallCount = 0
    }

    $batch = $itemsToTag[$i..([Math]::Min($i + $batchSize - 1, $itemsToTag.Count - 1))]
    $actions = $batch | ForEach-Object {
        @{
            action  = "tags_add"
            item_id = $_.item_id
            tags    = $tagToAdd
        }
    }

    $attempt = 1
    $success = $false
    do {
        try {
            Write-Host "Tagging batch $($i / $batchSize + 1), attempt $attempt..."
            $result = Invoke-PocketApi -Url "https://getpocket.com/v3/send" -Body @{
                consumer_key = $consumerKey
                access_token = $accessToken
                actions      = $actions
            }
            if ($result.status -eq 1) {
                $success = $true
                $successBatches++
                $apiCallCount++
            } else {
                throw "Non-success status returned."
            }
        } catch {
            Write-Warning "Batch failed (attempt $attempt): $_"
            Start-Sleep -Seconds ([math]::Pow(5, $attempt))
            $attempt++
        }
    } while (-not $success -and $attempt -le $maxRetries)

    if (-not $success) {
        $failedBatches++
        Write-Host "Skipping failed batch..."
        $batch | ForEach-Object { $_.item_id } | Out-File -Append -FilePath $failedBatchFile
    }

    Start-Sleep -Seconds 1
}

#endregion ----- MAIN --------------------

#region ----- SUMMARY --------------------

Write-Host ""
Write-Host "Tagging complete."
Write-Host ""
Write-Host "Total favorited items identified: $($allItems.Count)"
Write-Host "Items needing to be tagged:       $($itemsToTag.Count)"
Write-Host "Tag Added:                        '$tagToAdd'"
Write-Host "Successful batches:               $successBatches"
Write-Host "Successfully tagged items:        $($successBatches * $batchSize)"
Write-Host "Failed batches:                   $failedBatches"
Write-Host "Items unable to be tagged:        $($failedBatches * $batchSize)"
if (Test-Path $failedBatchFile) {
  Write-Host "Failed item IDs written to:       $failedBatchFile"
}
Write-Host "API calls made:                   $apiCallCount"
Write-Host ""

#endregion ----- SUMMARY --------------------
