<#
  .SYNOPSIS
  Converts Pocket CSV exports into wallabag-compatible JSON format.

  .DESCRIPTION
  This script processes one or more CSV files exported from Pocket, located in a given input directory.
  It performs the following operations:
    - Parses CSV lines safely, accounting for unquoted fields and embedded commas in titles and URLs.
    - Combines all entries into a single dataset.
    - Converts Unix timestamps to ISO 8601 datetime format.
    - Splits items into archived and unread sets.
    - Outputs JSON in chunks of a given size (default 1000 items per file).
    - Adds a unique tag in the format 'pocket2wallabag-YYYYMMDDHHMMSS' to each item's tag list.
    - If a `FavoriteTag` is provided, items that include that tag will be marked as `"is_starred": 1`.
    - Writes output files into a subdirectory under the input folder named after the generated tag.
    - Output files are named using the format: `{tag}_{unread/archive}_00.json`, etc.

  .PARAMETER InputDirectory
  The directory containing one or more Pocket-exported CSV files to convert.

  .PARAMETER FavoriteTag
  Optional. A tag used in Pocket to indicate items marked as "favorite".
  If provided, any item containing this tag will be exported with `"is_starred": 1`.

  .PARAMETER ChunkSize
  Optional. The maximum number of items to include in each output JSON file.
  Default is 1000.

  .EXAMPLE
  .\Convert-Pocket2Wallabag.ps1 -InputDirectory ".\path\to\PocketExports"

  .EXAMPLE
  .\Convert-Pocket2Wallabag.ps1 -InputDirectory ".\path\to\PocketExports" -FavoriteTag "pocket_fav" -ChunkSize 500

  .LINK
  https://github.com/qu13t0ne/pocket2wallabag

  .NOTES
  Author:         Mike Owens, mikeowens (at) fastmail (dot) com
  Website:        https://michaelowens.me
  GitLab:         https://gitlab.com/qu13t0ne
  GitHub:         https://github.com/qu13t0ne
  Bluesky:        https://bsky.app/profile/qu13t0ne.bsky.social
  Mastodon:       https://infosec.exchange/@qu13t0ne

  Pocket CSV files are assumed to have the following fields:
      title,url,time_added,tags,status
  Titles and URLs may contain commas and may or may not be quoted.
  The script uses regular expressions and pre-parsing to extract fields robustly.

#>

param (
  [Parameter(Mandatory = $true)]
  [string]$InputDirectory,

  [string]$FavoriteTag,

  [int]$ChunkSize = 1000
)

$InputDirectory = Resolve-Path -Path $InputDirectory | Select-Object -ExpandProperty Path

Add-Type -AssemblyName System.Web

#region ----- FUNCTIONS --------------------

function Get-LogicalLines {
  param ([string[]]$Lines)

  $buffer = ''
  $logicalLines = @()

  foreach ($line in $Lines) {
    $buffer += if ($buffer) { "`n$line" } else { $line }

    if ($buffer -match ',(https?://[^"]+)?"?,?(\d{10}),.*?,(unread|archive)$') {
      $logicalLines += $buffer
      $buffer = ''
    }
  }
  if ($buffer) { $logicalLines += $buffer }
  return $logicalLines
}

function Parse-RawPocketCsv {
  param ([string]$RawLine)

  Add-Type -AssemblyName Microsoft.VisualBasic

  $stringReader = New-Object System.IO.StringReader($RawLine)
  $parser = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($stringReader)
  $parser.TextFieldType = 'Delimited'
  $parser.SetDelimiters(',')
  $parser.HasFieldsEnclosedInQuotes = $true

  try {
    $fields = $parser.ReadFields()
    if ($fields.Count -lt 5) {
      Write-Warning "Incomplete CSV line: $RawLine"
      return $null
    }

    return [PSCustomObject]@{
      title      = $fields[0].Trim()
      url        = $fields[1].Trim()
      time_added = $fields[2].Trim()
      tags       = ($fields[3].Trim() -replace '\s+', '') -replace ',', '|'  # Normalize
      status     = $fields[4].Trim().ToLower()
    }
  } catch {
    Write-Warning "Error parsing line: $RawLine"
    return $null
  } finally {
    $parser.Close()
  }
}


function Get-CleanUrl {
  param ([string]$Url)

  # If it’s a Google redirect, extract real URL
  if ($Url -match 'https?://www\.google\.com/url\?.*?url=([^&]+)') {
    $encodedUrl = $matches[1]
    $decodedUrl = [System.Web.HttpUtility]::UrlDecode($encodedUrl)
    $Url = $decodedUrl
  }

  # Parse URL
  try {
    $uri = [uri]$Url
  } catch {
    return $Url  # Return as-is if not valid URI
  }

  $cleanQuery = [System.Web.HttpUtility]::ParseQueryString($uri.Query)
  $nullKeys = $cleanQuery.Keys | Where-Object { -not $_ }
  if ($nullKeys) {
    Write-Warning "Found null/empty query keys in: $Url"
  }

  foreach ($param in @('utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content', 'fbclid', 'gclid')) {
    $cleanQuery.Remove($param)
  }

  # Rebuild query string
  $queryString = if ($cleanQuery.Count -gt 0) {
    '?' + ($cleanQuery.Keys | Where-Object { $_ } | ForEach-Object { "$_=$($cleanQuery[$_])" }) -join '&'
  } else {
    ''
  }

  # Rebuild full clean URL
  $builder = [System.UriBuilder]::new($uri)
  $builder.Query = $queryString.TrimStart('?')
  return $builder.Uri.AbsoluteUri
}


function Write-JsonChunks {
  param (
    [Array]$Data,
    [string]$Type,
    [string]$OutputDir,
    [string]$Tag,
    [int]$ChunkSize
  )

  $chunks = [System.Collections.Generic.List[object]]::new()
  $i = 0
  foreach ($item in $Data) {
    if ($chunks.Count -ge $ChunkSize) {
      $fileName = '{0}_{1}_{2:D2}.json' -f $Tag, $Type, $i
      $file = Join-Path $OutputDir $fileName
      $chunks | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -Path $file
      $chunks.Clear()
      $i++
    }
    $chunks.Add($item)
  }

  if ($chunks.Count -gt 0) {
    $fileName = '{0}_{1}_{2:D2}.json' -f $Tag, $Type, $i
    $file = Join-Path $OutputDir $fileName
    $chunks | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -Path $file
  }
}

#endregion ----- FUNCTIONS --------------------

#region ----- MAIN --------------------

# Generate tag + output directory
$timestampTag = 'pocket2wallabag-' + (Get-Date -Format 'yyyyMMddHHmmss')
$outputDir = Join-Path $InputDirectory $timestampTag
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

# Read all lines from all CSVs, skip header
$allLines = Get-ChildItem -Path $InputDirectory -Filter *.csv |
  ForEach-Object { Get-Content $_.FullName -Raw } |
  ForEach-Object { $_ -split "`r?`n" } |
  Where-Object { $_ -and ($_ -notmatch '^title,url,time_added') }

# Combine lines into logical complete records
$logicalLines = Get-LogicalLines -Lines $allLines

# Parse logical lines
$parsedItems = @()
foreach ($line in $logicalLines) {
  $entry = Parse-RawPocketCsv -RawLine $line
  if ($entry) {
    $parsedItems += $entry
  }
}

# Transform to wallabag format
$entries = $parsedItems | ForEach-Object {
  $cleanedUrl = Get-CleanUrl $_.url
  if ($_.url -ne $cleanedUrl) {
    Write-Verbose "URL cleaned: $($_.url) -> $cleanedUrl"
  }

  [PSCustomObject]@{
    is_archived = if ($_.status -eq 'archive') { 1 } else { 0 }
    is_starred  = if ($FavoriteTag -and $_.tags -match "(?i)\b$FavoriteTag\b") { 1 } else { 0 }
    tags        = ($_.tags -split '\|') + $timestampTag | Where-Object { $_ -ne '' } | Sort-Object -Unique
    title       = $_.title
    url         = $cleanedUrl
    created_at  = ([DateTimeOffset]::FromUnixTimeSeconds([int]$_.time_added)).ToString('yyyy-MM-ddTHH:mm:sszzz')
    content     = ''
    mimetype    = 'text/html; charset=UTF-8'
    language    = 'en_US'
  }
}

# Split into archived/unread
$archived = $entries | Where-Object { $_.is_archived -eq 1 }
$unread = $entries | Where-Object { $_.is_archived -eq 0 }

# Write output files
Write-JsonChunks -Data $unread -Type 'unread' -OutputDir $outputDir -Tag $timestampTag -ChunkSize $ChunkSize
Write-JsonChunks -Data $archived -Type 'archive' -OutputDir $outputDir -Tag $timestampTag -ChunkSize $ChunkSize

#endregion ----- MAIN --------------------

#region ----- SUMMARY LOG --------------------

$totalCount = $entries.Count
$unreadCount = $unread.Count
$archivedCount = $archived.Count
$starredCount = ($entries | Where-Object { $_.is_starred -eq 1 }).Count

Write-Host ''
Write-Host '========== SUMMARY =========='
Write-Host "Total entries     : $totalCount"
Write-Host "Unread entries    : $unreadCount"
Write-Host "Archived entries  : $archivedCount"

if ($FavoriteTag) {
  Write-Host "Starred entries    : $starredCount  (based on tag '$FavoriteTag')"
}

Write-Host "Output directory   : $outputDir"
Write-Host "=============================`n"

#endregion ----- SUMMARY LOG --------------------
