<#
.SYNOPSIS
    Authenticate a Pocket user and obtain an access token.

.DESCRIPTION
    Automates the Pocket OAuth flow up to browser-based approval.
    Stores the access token for use in other scripts.

.PARAMETER ConsumerKey
    Your registered Pocket application's consumer key.

.PARAMETER RedirectUri
    A valid redirect URI — not actually used by Pocket, but required in API call.

.EXAMPLE
    .\Get-PocketAccessToken -ConsumerKey "abcdef123456"

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

param (
  [Parameter(Mandatory = $true)]
  [string]$ConsumerKey,

  [Parameter(Mandatory = $false)]
  [string]$RedirectUri = 'https://localhost'

  # [string]$TokenFilePath = (Join-Path $env:TEMP "pocket_token")
)

function Invoke-Pocket {
  param (
    [string]$Url,
    [hashtable]$Body
  )
  $json = $Body | ConvertTo-Json -Compress
  return Invoke-RestMethod -Uri $Url -Method POST -Body $json -ContentType 'application/json; charset=UTF-8'
}

Write-Host "`nRequesting Pocket request token..."
try {
  $tokenResponse = Invoke-Pocket -Url 'https://getpocket.com/v3/oauth/request' -Body @{
    consumer_key = $ConsumerKey
    redirect_uri = $RedirectUri
  }
  $requestToken = ($tokenResponse -split '=')[1]
  Write-Host "Request token received: $requestToken"
} catch {
  Write-Error "Failed to get request token: $_"
  exit 1
}

$authUrl = "https://getpocket.com/auth/authorize?request_token=$requestToken&redirect_uri=$RedirectUri"
Write-Host "`nOpening browser for authorization..."
Start-Process $authUrl

Write-Host 'Please authorize the app in your browser, then press Enter to continue...'
Read-Host

Write-Host "`n Exchanging request token for access token..."
try {
  $accessResponse = Invoke-Pocket -Url 'https://getpocket.com/v3/oauth/authorize' -Body @{
    consumer_key = $ConsumerKey
    code         = $requestToken
  }

  $parsedAccessResponse = $accessResponse -split '&' | ForEach-Object {
    $kv = $_ -split '=', 2
    @{ $kv[0] = $kv[1] }
  }
  $accessToken = $parsedAccessResponse.access_token
  $username = $parsedAccessResponse.username

  Write-Host 'Access token obtained!'
  Write-Host "    Username     : $username"
  Write-Host "    Consumer Key : $ConsumerKey"
  Write-Host "    Access Token : $accessToken"
  Write-Host ''
  Write-Host 'Run the following commands to load the consumer key and access token as environment'
  Write-Host 'variables in preparation for running the Update-PocketFavoritesWithTag.ps1 script.'
  Write-Host '(Just copy and paste the commands!)'
  Write-Host ''
  Write-Host "`$env:POCKET_CONSUMER_KEY = '$ConsumerKey'"
  Write-Host "`$env:POCKET_ACCESS_TOKEN = '$accessToken'"
  Write-Host ''

  # $accessToken | Out-File -Encoding utf8 -FilePath $TokenFilePath
  # Write-Host "`nAccess token saved to: $TokenFilePath"
} catch {
  Write-Error "Failed to exchange for access token: $_"
  exit 1
}
