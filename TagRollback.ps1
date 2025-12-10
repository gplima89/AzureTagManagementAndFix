<#
.SYNOPSIS
    Azure Resource Tag Rollback Script
    
.DESCRIPTION
    Restores Azure resource tags from a backup CSV file created by TagFix.ps1.
    Supports full rollback, selective rollback by resource group, and dry-run mode.
    
.PARAMETER BackupFile
    Path to the backup CSV file created by TagFix.ps1
    
.PARAMETER ResourceGroupName
    Optional: Rollback only resources in a specific resource group
    
.PARAMETER ResourceName
    Optional: Rollback only a specific resource by name
    
.PARAMETER WhatIf
    Shows what would happen without making actual changes
    
.PARAMETER Force
    Skip confirmation prompts
    
.EXAMPLE
    .\TagRollback.ps1 -BackupFile ".\TagReplacement_Environment_to_Env_20251210_143052.csv"
    
.EXAMPLE
    .\TagRollback.ps1 -BackupFile ".\backup.csv" -ResourceGroupName "rg-production" -WhatIf
    
.EXAMPLE
    .\TagRollback.ps1 -BackupFile ".\backup.csv" -ResourceName "vm-prod-01" -Force
    
.NOTES
    Version: 1.0
    Author: Guil Lima - Microsoft Canada - CSA
    Contact: guillima@microsoft.com
    Last Modified: December 10, 2025
    Requires: Az.Resources module
    
    IMPORTANT: Always test rollback in non-production first!
#>

[CmdletBinding(SupportsShouldProcess=$true)]
Param(
    [Parameter(Mandatory=$true, HelpMessage="Path to backup CSV file")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
        if (Test-Path $_) {
            $true
        } else {
            throw "Backup file not found: $_"
        }
    })]
    [String]$BackupFile,
    
    [Parameter(Mandatory=$false, HelpMessage="Filter by resource group name")]
    [String]$ResourceGroupName,
    
    [Parameter(Mandatory=$false, HelpMessage="Filter by specific resource name")]
    [String]$ResourceName,
    
    [Parameter(Mandatory=$false, HelpMessage="Skip confirmation prompts")]
    [Switch]$Force
)

#region Configuration
$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

# Script statistics
$script:SuccessCount = 0
$script:FailureCount = 0
$script:SkippedCount = 0
$script:StartTime = Get-Date
#endregion

#region Functions

function Write-Log {
    <#
    .SYNOPSIS
        Writes formatted log messages with timestamp and color coding
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("Info", "Success", "Warning", "Error", "Progress")]
        [string]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "Success"  { "Green" }
        "Warning"  { "Yellow" }
        "Error"    { "Red" }
        "Progress" { "Cyan" }
        default    { "White" }
    }
    
    $prefix = switch ($Level) {
        "Success"  { "[✓]" }
        "Warning"  { "[!]" }
        "Error"    { "[✗]" }
        "Progress" { "[→]" }
        default    { "[i]" }
    }
    
    Write-Host "[$timestamp] $prefix $Message" -ForegroundColor $color
}

function Test-AzureConnection {
    <#
    .SYNOPSIS
        Tests and establishes Azure connection
    #>
    [CmdletBinding()]
    param()
    
    try {
        Write-Log "Checking Azure connection..." -Level Info
        
        # Check if already connected
        $context = Get-AzContext -ErrorAction SilentlyContinue
        
        if ($context) {
            Write-Log "Connected to Azure as: $($context.Account.Id)" -Level Success
            Write-Log "Subscription: $($context.Subscription.Name) ($($context.Subscription.Id))" -Level Info
            return $true
        }
        
        # Not connected, initiate connection
        Write-Log "Not connected. Initiating Azure login..." -Level Warning
        $connection = Connect-AzAccount -ErrorAction Stop
        
        if ($connection) {
            Write-Log "Successfully connected to Azure" -Level Success
            return $true
        }
        
        return $false
    }
    catch {
        Write-Log "Failed to connect to Azure: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Import-BackupData {
    <#
    .SYNOPSIS
        Imports and validates backup CSV file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    
    try {
        Write-Log "Importing backup file: $FilePath" -Level Progress
        
        # Import CSV
        $backupData = Import-Csv -Path $FilePath -ErrorAction Stop
        
        if (-not $backupData -or $backupData.Count -eq 0) {
            Write-Log "Backup file is empty or invalid" -Level Error
            return $null
        }
        
        # Validate required columns
        $requiredColumns = @('Name', 'ResourceId', 'OldTagName', 'NewTagName', 'TagValue')
        $actualColumns = $backupData[0].PSObject.Properties.Name
        
        foreach ($column in $requiredColumns) {
            if ($column -notin $actualColumns) {
                Write-Log "Backup file missing required column: $column" -Level Error
                return $null
            }
        }
        
        Write-Log "Successfully imported $($backupData.Count) records from backup" -Level Success
        
        # Display backup metadata
        $firstRecord = $backupData[0]
        Write-Log "Backup Details:" -Level Info
        Write-Log "  Old Tag Name: $($firstRecord.OldTagName)" -Level Info
        Write-Log "  New Tag Name: $($firstRecord.NewTagName)" -Level Info
        Write-Log "  Backup Date: $($firstRecord.Timestamp)" -Level Info
        
        return $backupData
    }
    catch {
        Write-Log "Failed to import backup file: $($_.Exception.Message)" -Level Error
        return $null
    }
}

function Test-ResourceExists {
    <#
    .SYNOPSIS
        Checks if a resource still exists in Azure
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ResourceId
    )
    
    try {
        $resource = Get-AzResource -ResourceId $ResourceId -ErrorAction SilentlyContinue
        return ($null -ne $resource)
    }
    catch {
        return $false
    }
}

function Restore-ResourceTags {
    <#
    .SYNOPSIS
        Restores tags for a single resource
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$BackupRecord,
        
        [Parameter(Mandatory=$false)]
        [switch]$WhatIfMode
    )
    
    try {
        Write-Log "Processing: $($BackupRecord.Name)" -Level Progress
        
        # Check if resource exists
        if (-not (Test-ResourceExists -ResourceId $BackupRecord.ResourceId)) {
            Write-Log "Resource no longer exists: $($BackupRecord.Name)" -Level Warning
            $script:SkippedCount++
            return $false
        }
        
        # Get current resource
        $resource = Get-AzResource -ResourceId $BackupRecord.ResourceId -ErrorAction Stop
        
        # Clone current tags
        $currentTags = @{}
        if ($resource.Tags) {
            foreach ($key in $resource.Tags.Keys) {
                $currentTags[$key] = $resource.Tags[$key]
            }
        }
        
        Write-Verbose "Current tags: $($currentTags.Keys -join ', ')"
        
        # Check if new tag exists (the one we want to remove)
        $newTagExists = $currentTags.ContainsKey($BackupRecord.NewTagName)
        $oldTagExists = $currentTags.ContainsKey($BackupRecord.OldTagName)
        
        if (-not $newTagExists -and $oldTagExists) {
            Write-Log "Resource $($BackupRecord.Name) already appears to be rolled back (has old tag, missing new tag)" -Level Warning
            $script:SkippedCount++
            return $false
        }
        
        if (-not $newTagExists -and -not $oldTagExists) {
            Write-Log "Resource $($BackupRecord.Name) has neither old nor new tag. Manual intervention may be needed." -Level Warning
            $script:SkippedCount++
            return $false
        }
        
        # Prepare rollback actions
        $actions = @()
        
        # Remove new tag if present
        if ($newTagExists) {
            $actions += "Remove tag: $($BackupRecord.NewTagName)"
            if (-not $WhatIfMode) {
                $currentTags.Remove($BackupRecord.NewTagName)
            }
        }
        
        # Restore old tag
        $actions += "Restore tag: $($BackupRecord.OldTagName) = $($BackupRecord.TagValue)"
        if (-not $WhatIfMode) {
            $currentTags[$BackupRecord.OldTagName] = $BackupRecord.TagValue
        }
        
        # Display actions
        foreach ($action in $actions) {
            Write-Log "  → $action" -Level Info
        }
        
        # Apply changes
        if ($WhatIfMode) {
            Write-Log "WhatIf: Would rollback tags for $($BackupRecord.Name)" -Level Info
            $script:SuccessCount++
            return $true
        }
        
        if ($PSCmdlet.ShouldProcess($BackupRecord.Name, "Rollback tags")) {
            Update-AzTag -ResourceId $BackupRecord.ResourceId -Tag $currentTags -Operation Replace -ErrorAction Stop
            
            # Verify rollback
            Start-Sleep -Milliseconds 500
            $verifyResource = Get-AzResource -ResourceId $BackupRecord.ResourceId -ErrorAction SilentlyContinue
            
            if ($verifyResource) {
                $hasOldTag = $verifyResource.Tags.ContainsKey($BackupRecord.OldTagName)
                $hasNewTag = $verifyResource.Tags.ContainsKey($BackupRecord.NewTagName)
                
                if ($hasOldTag -and -not $hasNewTag) {
                    Write-Log "✓ Successfully rolled back: $($BackupRecord.Name)" -Level Success
                    $script:SuccessCount++
                    return $true
                }
                else {
                    Write-Log "Verification failed for $($BackupRecord.Name). Rollback may be incomplete." -Level Warning
                    $script:FailureCount++
                    return $false
                }
            }
        }
        
        return $true
    }
    catch {
        Write-Log "Failed to rollback $($BackupRecord.Name): $($_.Exception.Message)" -Level Error
        $script:FailureCount++
        return $false
    }
}

function Show-Summary {
    <#
    .SYNOPSIS
        Displays execution summary
    #>
    [CmdletBinding()]
    param()
    
    $endTime = Get-Date
    $duration = $endTime - $script:StartTime
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "ROLLBACK SUMMARY" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Start Time:              $($script:StartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor White
    Write-Host "End Time:                $($endTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor White
    Write-Host "Duration:                $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor White
    Write-Host "Total Resources:         $($script:SuccessCount + $script:FailureCount + $script:SkippedCount)" -ForegroundColor White
    Write-Host "Successfully Rolled Back: $($script:SuccessCount)" -ForegroundColor Green
    Write-Host "Failed:                  $($script:FailureCount)" -ForegroundColor Red
    Write-Host "Skipped:                 $($script:SkippedCount)" -ForegroundColor Yellow
    Write-Host "========================================`n" -ForegroundColor Cyan
}

#endregion

#region Main Execution

try {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Azure Resource Tag Rollback Tool" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    # Test Azure connection
    if (-not (Test-AzureConnection)) {
        Write-Log "Cannot proceed without Azure connection. Exiting." -Level Error
        exit 1
    }
    
    # Import backup data
    $backupData = Import-BackupData -FilePath $BackupFile
    
    if (-not $backupData) {
        Write-Log "Failed to import backup data. Exiting." -Level Error
        exit 1
    }
    
    # Apply filters if specified
    $filteredData = $backupData
    
    if ($ResourceGroupName) {
        Write-Log "Filtering by Resource Group: $ResourceGroupName" -Level Info
        $filteredData = $filteredData | Where-Object { $_.ResourceGroupName -eq $ResourceGroupName }
    }
    
    if ($ResourceName) {
        Write-Log "Filtering by Resource Name: $ResourceName" -Level Info
        $filteredData = $filteredData | Where-Object { $_.Name -like "*$ResourceName*" }
    }
    
    if ($filteredData.Count -eq 0) {
        Write-Log "No resources match the specified filters. Exiting." -Level Warning
        exit 0
    }
    
    # Display resources to be rolled back
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Resources to Rollback" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    $filteredData | Select-Object Name, ResourceGroupName, ResourceType, Location, `
        @{N="Old Tag";E={$_.OldTagName}}, `
        @{N="New Tag";E={$_.NewTagName}}, `
        @{N="Value";E={$_.TagValue}} | Format-Table -AutoSize
    
    Write-Host "Operation: Restore tag '$($filteredData[0].OldTagName)' from '$($filteredData[0].NewTagName)'" -ForegroundColor Yellow
    Write-Host "Total Resources: $($filteredData.Count)" -ForegroundColor Yellow
    
    # Confirmation prompt (unless Force or WhatIf)
    if (-not $Force -and -not $WhatIfPreference) {
        $confirmation = Read-Host -Prompt "`nDo you want to proceed with this rollback? (Y/N)"
        
        if ($confirmation -ne "Y" -and $confirmation -ne "y") {
            Write-Log "Rollback cancelled by user." -Level Warning
            exit 0
        }
    }
    
    Write-Log "Starting rollback operation..." -Level Progress
    
    # Process each resource
    $progress = 0
    foreach ($record in $filteredData) {
        $progress++
        Write-Progress -Activity "Rolling Back Tags" `
            -Status "Processing $($record.Name)" `
            -PercentComplete (($progress / $filteredData.Count) * 100)
        
        Restore-ResourceTags -BackupRecord $record -WhatIfMode:$WhatIfPreference
    }
    
    Write-Progress -Activity "Rolling Back Tags" -Completed
    
    # Show summary
    Show-Summary
    
    if ($WhatIfPreference) {
        Write-Log "WhatIf mode completed. No actual changes were made." -Level Info
    }
    else {
        Write-Log "Rollback operation completed." -Level Success
        
        if ($script:FailureCount -gt 0) {
            Write-Log "Some resources failed to rollback. Review the logs above for details." -Level Warning
        }
    }
}
catch {
    Write-Log "Critical error occurred: $($_.Exception.Message)" -Level Error
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level Error
    Show-Summary
    exit 1
}
finally {
    Write-Progress -Activity "Rolling Back Tags" -Completed -ErrorAction SilentlyContinue
}

#endregion
