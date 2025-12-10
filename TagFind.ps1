
<#
.SYNOPSIS
  Fetch all Azure resources that have the tag key "9381" using Azure Resource Graph with paging.

.PARAMETER TagKey
  The tag key to search for. Defaults to "9381".

.PARAMETER BatchSize
  Page size for Search-AzGraph. Max is 1000; default 1000.

.PARAMETER Subscriptions
  Optional subscription IDs to scope the query. If empty and UseTenantScope is used,
  the query runs tenant-wide (subject to your RBAC).

.PARAMETER UseTenantScope
  Switch to run the query across the entire tenant. Ignored if Subscriptions are provided.

.PARAMETER OutputPath
  Path to write CSV output. Defaults to .\azure_resources_with_tag_9381.csv

.EXAMPLE
  .\Get-Arg-TaggedResources.ps1 -UseTenantScope

.EXAMPLE
  .\Get-Arg-TaggedResources.ps1 -Subscriptions "00000000-0000-0000-0000-000000000001","00000000-0000-0000-0000-000000000002" -OutputPath .\out.csv
#>

param(
  [string]$TagKey = "9381",
  [int]$BatchSize = 1000,
  [string[]]$Subscriptions = @(),
  [switch]$UseTenantScope,
  [string]$OutputPath = ".\azure_resources_with_tag_9381.csv"
)

# --- Modules & Context ---
Write-Host "Loading Az modules..." -ForegroundColor Cyan
Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.ResourceGraph -ErrorAction Stop

if (-not (Get-AzContext)) {
  Write-Host "Connecting to Azure..." -ForegroundColor Cyan
  Connect-AzAccount | Out-Null
}

# Build scope parameters for Search-AzGraph
$graphScopeParams = @{}
if ($Subscriptions.Count -gt 0) {
  $graphScopeParams.Subscription = $Subscriptions
  Write-Host "Scoped to subscriptions: $($Subscriptions -join ', ')" -ForegroundColor Cyan
} elseif ($UseTenantScope) {
  $graphScopeParams.UseTenantScope = $true
  Write-Host "Using tenant-wide scope (RBAC applies)..." -ForegroundColor Cyan
} else {
  # Default to current context subscription if neither provided nor UseTenantScope
  $currentSub = (Get-AzContext).Subscription.Id
  $graphScopeParams.Subscription = $currentSub
  Write-Host "Defaulting to current subscription: $currentSub" -ForegroundColor Cyan
}

# --- KQL (Count) ---
# Direct dynamic property access on tags['<TagKey>'] is the fastest way to test existence.
$kqlCount = @"
resources
| where isnotnull(tags['$TagKey'])
| summarize Count = count()
"@

Write-Host "Counting resources with tag key '$TagKey'..." -ForegroundColor Cyan
try {
  $countResult = Search-AzGraph -Query $kqlCount @graphScopeParams
  $total = 0
  if ($countResult -and $countResult.Count -is [int]) {
    $total = $countResult.Count
  } elseif ($countResult | Get-Member -Name Count -MemberType NoteProperty) {
    $total = [int]$countResult.Count
  }

  Write-Host "Found $total resources with tag key '$TagKey'." -ForegroundColor Green
} catch {
  Write-Error "Failed to run count query: $($_.Exception.Message)"
  throw
}

if ($total -le 0) {
  Write-Warning "No resources found with tag key '$TagKey'."
  return
}

# --- KQL (Paged fetch) ---
# Project only the fields you care about to reduce payload and improve performance.
$kqlPage = @"
resources
| where isnotnull(tags['$TagKey'])
| project
    id,
    name,
    type,
    subscriptionId,
    resourceGroup,
    location,
    tagValue = tostring(tags['$TagKey'])
"@

# Results accumulator – List is more memory-efficient than constantly re-sizing PowerShell arrays.
$all = New-Object System.Collections.Generic.List[object]
$skip = 0

# Helper for backoff on transient failures
function Invoke-ArgPagedQuery {
  param(
    [string]$Query,
    [int]$First,
    [int]$Skip,
    [hashtable]$ScopeParams
  )

  $attempt = 0
  $maxAttempts = 5
  $delayMs = 500

  while ($attempt -lt $maxAttempts) {
    try {
      # Skip parameter must be >= 1 for Search-AzGraph, so only include it if > 0
      if ($Skip -gt 0) {
        return Search-AzGraph -Query $Query -First $First -Skip $Skip @ScopeParams
      } else {
        return Search-AzGraph -Query $Query -First $First @ScopeParams
      }
    } catch {
      $attempt++
      Write-Warning "ARG query failed (attempt $attempt/$maxAttempts, skip=$Skip): $($_.Exception.Message)"
      Start-Sleep -Milliseconds $delayMs
      # Exponential backoff
      $delayMs = [Math]::Min($delayMs * 2, 8000)
    }
  }

  throw "ARG paged query failed after $maxAttempts attempts (skip=$Skip)."
}

Write-Host "Starting paged retrieval in batches of $BatchSize..." -ForegroundColor Cyan
while ($skip -lt $total) {
  $rangeEnd = [Math]::Min($skip + $BatchSize - 1, $total - 1)
  Write-Progress -Activity "Fetching resources with tag '$TagKey'" `
                 -Status "Batch: $skip..$rangeEnd of $total" `
                 -PercentComplete ([math]::Round(($skip / $total) * 100, 2))

  $page = Invoke-ArgPagedQuery -Query $kqlPage -First $BatchSize -Skip $skip -ScopeParams $graphScopeParams
  
  if ($page) {
    # PSResourceGraphResponse object implements IEnumerable and contains the results
    # Access items directly by enumerating the response
    $itemsInBatch = 0
    foreach ($item in $page) {
      if ($item) {
        $all.Add($item)
        $itemsInBatch++
      }
    }
    
    Write-Verbose "Retrieved $itemsInBatch resources in this batch (Total so far: $($all.Count))"
  }

  $skip += $BatchSize
}

Write-Progress -Activity "Fetching resources with tag '$TagKey'" -Completed

# Optional de-dup by resource id (paranoia only; ARG should already be unique)
if ($all.Count -gt 0) {
  $deduped = $all | Group-Object id | ForEach-Object { $_.Group[0] }
  
  Write-Host "`n========================================" -ForegroundColor Cyan
  Write-Host "RESOURCES WITH TAG: $TagKey" -ForegroundColor Cyan
  Write-Host "========================================" -ForegroundColor Cyan
  
  # Display results in a formatted table
  $deduped | Select-Object name, type, resourceGroup, location, subscriptionId, tagValue, id | Format-Table -AutoSize
  
  Write-Host "========================================" -ForegroundColor Cyan
  Write-Host "Total resources found: $($deduped.Count)" -ForegroundColor Green
  Write-Host "========================================`n" -ForegroundColor Cyan
  
  # Write CSV output if needed
  if ($OutputPath) {
    Write-Host "Writing CSV file to: $OutputPath ..." -ForegroundColor Cyan
    $deduped |
      Select-Object id, name, type, subscriptionId, resourceGroup, location, tagValue |
      Export-Csv -NoTypeInformation -Encoding UTF8 -Path $OutputPath
    Write-Host "CSV file written successfully!" -ForegroundColor Green
  }
} else {
  Write-Warning "No resources were retrieved from Azure Resource Graph."
  Write-Host "`nThis could happen if:" -ForegroundColor Yellow
  Write-Host "  - The count query result was cached but resources have since been deleted" -ForegroundColor Yellow
  Write-Host "  - There's a delay in Azure Resource Graph indexing (data can be up to 5 minutes old)" -ForegroundColor Yellow  
  Write-Host "  - The tag exists but on resources you don't have RBAC permissions to view" -ForegroundColor Yellow
  Write-Host "`nRecommended Actions:" -ForegroundColor Cyan
  Write-Host "  1. Wait 5-10 minutes and retry (Resource Graph cache refresh)" -ForegroundColor Gray
  Write-Host "  2. Verify the tag exists using Azure Portal or CLI" -ForegroundColor Gray
  Write-Host "  3. Check permissions: Get-AzRoleAssignment -SignInName (Get-AzContext).Account.Id" -ForegroundColor Gray
  Write-Host "`nNote: This script uses Azure Resource Graph API for optimal performance with 200K+ resources across 700+ subscriptions." -ForegroundColor Gray
  return
}
