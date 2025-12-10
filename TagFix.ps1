<#
.SYNOPSIS
    Azure Resource Tag Replacement Script
    
.DESCRIPTION
    Replaces a specific tag name with a new tag name across Azure Virtual Machines.
    Creates a backup CSV file before making changes and validates all operations.
    
.PARAMETER TagToReplace
    The existing tag name that you want to replace
    
.PARAMETER TagNewName
    The new tag name that will replace the old tag
    
.PARAMETER ResourceType
    The resource type to filter. Default: Microsoft.Compute/virtualMachines
    
.PARAMETER SubscriptionId
    Optional: Specific subscription ID to target. If not provided, uses current context.
    
.EXAMPLE
    .\TagFix.ps1 -TagToReplace "Environment" -TagNewName "Env"
    
.EXAMPLE
    .\TagFix.ps1
    (Will prompt for parameters interactively)
    
.NOTES
    Version: 2.0
    Author: Azure Infrastructure Team
    Last Modified: December 10, 2025
    Requires: Az.Resources module
#>

[CmdletBinding(SupportsShouldProcess=$true)]
Param(
    [Parameter(Mandatory=$false, HelpMessage="The tag name to be replaced")]
    [ValidateNotNullOrEmpty()]
    [String]$TagToReplace,
    
    [Parameter(Mandatory=$false, HelpMessage="The new tag name")]
    [ValidateNotNullOrEmpty()]
    [String]$TagNewName,
    
    [Parameter(Mandatory=$false, HelpMessage="Resource type to filter")]
    [ValidateNotNullOrEmpty()]
    [String]$ResourceType = "Microsoft.Compute/virtualMachines",
    
    [Parameter(Mandatory=$false, HelpMessage="Specific subscription ID")]
    [String]$SubscriptionId
)

#region Configuration
$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

# Script statistics
$script:SuccessCount = 0
$script:FailureCount = 0
$script:SkippedCount = 0
#endregion

#region Functions

function Write-Log {
    <#
    .SYNOPSIS
        Writes formatted log messages with timestamp
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("Info", "Success", "Warning", "Error")]
        [string]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "Success" { "Green" }
        "Warning" { "Yellow" }
        "Error"   { "Red" }
        default   { "White" }
    }
    
    $prefix = switch ($Level) {
        "Success" { "[✓]" }
        "Warning" { "[!]" }
        "Error"   { "[✗]" }
        default   { "[i]" }
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
            Write-Log "Already connected to Azure as: $($context.Account.Id)" -Level Success
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

function Test-TagExists {
    <#
    .SYNOPSIS
        Validates if a tag exists on any resources
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$TagName,
        
        [Parameter(Mandatory=$false)]
        [string]$ResourceType
    )
    
    try {
        Write-Log "Searching for resources with tag '$TagName'..." -Level Info
        
        $params = @{
            TagName = $TagName
            ErrorAction = 'Stop'
        }
        
        if ($ResourceType) {
            $resources = Get-AzResource @params | Where-Object { $_.ResourceType -eq $ResourceType }
        }
        else {
            $resources = Get-AzResource @params
        }
        
        if ($resources) {
            Write-Log "Found $($resources.Count) resource(s) with tag '$TagName'" -Level Success
            return $resources
        }
        else {
            Write-Log "No resources found with tag '$TagName'" -Level Warning
            return $null
        }
    }
    catch {
        Write-Log "Error searching for tag: $($_.Exception.Message)" -Level Error
        return $null
    }
}

function Backup-ResourceTags {
    <#
    .SYNOPSIS
        Creates a backup of resource tags to CSV
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$Resource,
        
        [Parameter(Mandatory=$true)]
        [string]$OldTagName,
        
        [Parameter(Mandatory=$true)]
        [string]$NewTagName,
        
        [Parameter(Mandatory=$true)]
        [string]$LogFilePath
    )
    
    try {
        # Safely get tag value
        $tagValue = if ($Resource.Tags.ContainsKey($OldTagName)) {
            $Resource.Tags[$OldTagName]
        } else {
            ""
        }
        
        # Create backup object
        $backup = [PSCustomObject]@{
            Timestamp         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Name              = $Resource.Name
            ResourceGroupName = $Resource.ResourceGroupName
            ResourceId        = $Resource.ResourceId
            ResourceType      = $Resource.ResourceType
            Location          = $Resource.Location
            OldTagName        = $OldTagName
            NewTagName        = $NewTagName
            TagValue          = $tagValue
            AllTags           = ($Resource.Tags.Keys -join '; ')
            Status            = "Pending"
        }
        
        # Export to CSV
        $backup | Export-Csv -Path $LogFilePath -NoTypeInformation -Append -ErrorAction Stop
        
        return $true
    }
    catch {
        Write-Log "Failed to backup tags for $($Resource.Name): $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Update-ResourceTag {
    <#
    .SYNOPSIS
        Updates a resource tag with validation
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$Resource,
        
        [Parameter(Mandatory=$true)]
        [string]$OldTagName,
        
        [Parameter(Mandatory=$true)]
        [string]$NewTagName
    )
    
    try {
        Write-Log "Processing: $($Resource.Name)" -Level Info
        
        # Validate resource has the old tag
        if (-not $Resource.Tags.ContainsKey($OldTagName)) {
            Write-Log "Resource $($Resource.Name) does not have tag '$OldTagName'. Skipping." -Level Warning
            $script:SkippedCount++
            return $false
        }
        
        # Get tag value
        $tagValue = $Resource.Tags[$OldTagName]
        
        # Check if new tag already exists
        if ($Resource.Tags.ContainsKey($NewTagName)) {
            Write-Log "Resource $($Resource.Name) already has tag '$NewTagName'. Checking if values match..." -Level Warning
            
            if ($Resource.Tags[$NewTagName] -eq $tagValue) {
                Write-Log "Tag '$NewTagName' already exists with same value. Removing old tag only." -Level Info
            }
            else {
                Write-Log "Tag '$NewTagName' exists with different value. This may cause data loss. Skipping." -Level Warning
                $script:SkippedCount++
                return $false
            }
        }
        
        # Clone tags hashtable
        $newTags = @{}
        foreach ($key in $Resource.Tags.Keys) {
            $newTags[$key] = $Resource.Tags[$key]
        }
        
        # Remove old tag
        $removed = $newTags.Remove($OldTagName)
        if (-not $removed) {
            Write-Log "Failed to remove old tag '$OldTagName'" -Level Error
            $script:FailureCount++
            return $false
        }
        
        # Add new tag (if not already present)
        if (-not $newTags.ContainsKey($NewTagName)) {
            $newTags[$NewTagName] = $tagValue
        }
        
        # Update tags on resource
        $updateResult = Update-AzTag -ResourceId $Resource.ResourceId -Tag $newTags -Operation Replace -ErrorAction Stop
        
        if ($updateResult) {
            Write-Log "Successfully updated tags for $($Resource.Name)" -Level Success
            
            # Verify the update
            Start-Sleep -Milliseconds 500  # Brief pause for Azure to process
            $updatedResource = Get-AzResource -ResourceId $Resource.ResourceId -ErrorAction SilentlyContinue
            
            if ($updatedResource -and $updatedResource.Tags.ContainsKey($NewTagName) -and -not $updatedResource.Tags.ContainsKey($OldTagName)) {
                Write-Log "Verified: Tag replacement successful for $($Resource.Name)" -Level Success
                $script:SuccessCount++
                return $true
            }
            else {
                Write-Log "Verification failed for $($Resource.Name). Tags may not have updated correctly." -Level Warning
                $script:FailureCount++
                return $false
            }
        }
        
        return $true
    }
    catch {
        Write-Log "Failed to update tags for $($Resource.Name): $($_.Exception.Message)" -Level Error
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
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "EXECUTION SUMMARY" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Total Resources Processed: $($script:SuccessCount + $script:FailureCount + $script:SkippedCount)" -ForegroundColor White
    Write-Host "Successfully Updated:      $($script:SuccessCount)" -ForegroundColor Green
    Write-Host "Failed:                    $($script:FailureCount)" -ForegroundColor Red
    Write-Host "Skipped:                   $($script:SkippedCount)" -ForegroundColor Yellow
    Write-Host "========================================`n" -ForegroundColor Cyan
}

#endregion

#region Main Execution

try {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Azure Resource Tag Replacement Tool" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    # Get parameters if not provided
    if (-not $TagToReplace) {
        $TagToReplace = Read-Host -Prompt "Enter the tag name to replace"
        if (-not $TagToReplace) {
            Write-Log "Tag name is required. Exiting." -Level Error
            exit 1
        }
    }
    
    if (-not $TagNewName) {
        $TagNewName = Read-Host -Prompt "Enter the new tag name"
        if (-not $TagNewName) {
            Write-Log "New tag name is required. Exiting." -Level Error
            exit 1
        }
    }
    
    # Validate tag names are different
    if ($TagToReplace -eq $TagNewName) {
        Write-Log "Old and new tag names are identical. Nothing to do." -Level Warning
        exit 0
    }
    
    # Test Azure connection
    if (-not (Test-AzureConnection)) {
        Write-Log "Cannot proceed without Azure connection. Exiting." -Level Error
        exit 1
    }
    
    # Set subscription if specified
    if ($SubscriptionId) {
        Write-Log "Setting subscription context to: $SubscriptionId" -Level Info
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
    }
    
    # Create log file
    $currentDate = Get-Date -Format "yyyyMMdd_HHmmss"
    $logFileName = ".\TagReplacement_$($TagToReplace)_to_$($TagNewName)_$currentDate.csv"
    Write-Log "Backup log will be saved to: $logFileName" -Level Info
    
    # Search for resources with the tag
    $resourceList = Test-TagExists -TagName $TagToReplace -ResourceType $ResourceType
    
    if (-not $resourceList -or $resourceList.Count -eq 0) {
        Write-Log "No resources found with tag '$TagToReplace' of type '$ResourceType'. Exiting." -Level Warning
        exit 0
    }
    
    # Display resources found
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Resources Found with Tag: $TagToReplace" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    $resourceList | Select-Object Name, ResourceGroupName, ResourceType, Location, `
        @{N="CurrentTag";E={$TagToReplace}}, `
        @{N="CurrentValue";E={$_.Tags[$TagToReplace]}} | Format-Table -AutoSize
    
    # Confirm action
    Write-Host "Operation: Replace tag '$TagToReplace' with '$TagNewName'" -ForegroundColor Yellow
    Write-Host "Resource Type: $ResourceType" -ForegroundColor Yellow
    Write-Host "Total Resources: $($resourceList.Count)" -ForegroundColor Yellow
    
    $confirmation = Read-Host -Prompt "`nDo you want to proceed with this replacement? (Y/N)"
    
    if ($confirmation -ne "Y" -and $confirmation -ne "y") {
        Write-Log "Operation cancelled by user." -Level Warning
        exit 0
    }
    
    Write-Log "Starting tag replacement operation..." -Level Info
    
    # Process each resource
    $progress = 0
    foreach ($resource in $resourceList) {
        $progress++
        Write-Progress -Activity "Replacing Tags" -Status "Processing $($resource.Name)" -PercentComplete (($progress / $resourceList.Count) * 100)
        
        # Backup current state
        $backupSuccess = Backup-ResourceTags -Resource $resource -OldTagName $TagToReplace -NewTagName $TagNewName -LogFilePath $logFileName
        
        if (-not $backupSuccess) {
            Write-Log "Failed to backup tags for $($resource.Name). Skipping update." -Level Warning
            $script:SkippedCount++
            continue
        }
        
        # Update the tag
        $updateSuccess = Update-ResourceTag -Resource $resource -OldTagName $TagToReplace -NewTagName $TagNewName
    }
    
    Write-Progress -Activity "Replacing Tags" -Completed
    
    # Show summary
    Show-Summary
    
    Write-Log "Backup and audit log saved to: $logFileName" -Level Success
    Write-Log "Tag replacement operation completed." -Level Success
}
catch {
    Write-Log "Critical error occurred: $($_.Exception.Message)" -Level Error
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level Error
    Show-Summary
    exit 1
}

#endregion