<#
.SYNOPSIS
    Azure Resource Tag Inventory and Export Tool
    
.DESCRIPTION
    Collects all Azure resources and their tags using Azure Resource Graph API,
    then exports the data to a CSV file with dynamic columns for each unique tag name.
    Supports tenant-wide queries and handles large datasets with pagination.
    
.PARAMETER OutputPath
    The file path where the CSV report will be saved. Default: C:\temp\TagsReport2.csv
    
.PARAMETER UseTenantScope
    Switch to query across all subscriptions in the tenant. Default: $true
    
.PARAMETER ResourceType
    Optional: Filter resources by specific type (e.g., "Microsoft.Compute/virtualMachines")
    
.PARAMETER PageSize
    Number of resources to retrieve per page. Default: 1000 (max supported by Resource Graph)
    
.PARAMETER ExcludeSystemTags
    Switch to exclude system-managed tags (disk-related, hidden-link, etc.)
    
.EXAMPLE
    .\TagWorkshop_v2.ps1
    (Uses default settings: exports to C:\temp\TagsReport2.csv with tenant scope)
    
.EXAMPLE
    .\TagWorkshop_v2.ps1 -OutputPath "D:\Reports\AzureTags.csv" -ResourceType "Microsoft.Compute/virtualMachines"
    
.NOTES
    Version: 2.0
    Author: Azure Infrastructure Team
    Last Modified: December 10, 2025
    Requires: Az.Accounts, Az.ResourceGraph modules
    
    Performance Notes:
    - Uses Azure Resource Graph for efficient querying (much faster than Get-AzResource)
    - Handles pagination automatically for large tenants
    - Dynamic class creation allows flexible tag schema
#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory=$false, HelpMessage="Output CSV file path")]
    [ValidateNotNullOrEmpty()]
    [String]$OutputPath = "C:\temp\TagsReport2.csv",
    
    [Parameter(Mandatory=$false, HelpMessage="Query across all subscriptions in tenant")]
    [Switch]$UseTenantScope = $true,
    
    [Parameter(Mandatory=$false, HelpMessage="Filter by specific resource type")]
    [String]$ResourceType,
    
    [Parameter(Mandatory=$false, HelpMessage="Number of resources per page (max 1000)")]
    [ValidateRange(1, 1000)]
    [Int]$PageSize = 1000,
    
    [Parameter(Mandatory=$false, HelpMessage="Exclude system-managed tags")]
    [Switch]$ExcludeSystemTags = $true
)

#region Configuration
$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

# Script statistics
$script:StartTime = Get-Date
$script:ResourcesProcessed = 0
$script:UniqueTagsFound = 0
$script:ResourcesWithTags = 0
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

function Test-RequiredModules {
    <#
    .SYNOPSIS
        Validates and imports required PowerShell modules
    #>
    [CmdletBinding()]
    param()
    
    try {
        Write-Log "Checking required modules..." -Level Info
        
        $requiredModules = @(
            @{Name = "Az.Accounts"; MinVersion = "2.0.0"},
            @{Name = "Az.ResourceGraph"; MinVersion = "0.7.0"}
        )
        
        foreach ($module in $requiredModules) {
            Write-Verbose "Checking module: $($module.Name)"
            
            $installedModule = Get-Module -ListAvailable -Name $module.Name | 
                Where-Object { $_.Version -ge [Version]$module.MinVersion } | 
                Select-Object -First 1
            
            if ($installedModule) {
                Write-Verbose "Module $($module.Name) version $($installedModule.Version) found"
                
                # Import if not already loaded
                if (-not (Get-Module -Name $module.Name)) {
                    Write-Verbose "Importing module: $($module.Name)"
                    Import-Module -Name $module.Name -Global -ErrorAction Stop
                }
            }
            else {
                Write-Log "Module $($module.Name) version $($module.MinVersion) or higher is required but not found." -Level Error
                Write-Log "Install with: Install-Module -Name $($module.Name) -Force" -Level Info
                return $false
            }
        }
        
        Write-Log "All required modules are available and loaded" -Level Success
        return $true
    }
    catch {
        Write-Log "Error checking modules: $($_.Exception.Message)" -Level Error
        return $false
    }
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
            Write-Log "Already connected to Azure" -Level Success
            Write-Log "Account: $($context.Account.Id)" -Level Info
            Write-Log "Tenant: $($context.Tenant.Id)" -Level Info
            
            if ($UseTenantScope) {
                Write-Log "Mode: Tenant-wide query (all subscriptions)" -Level Info
            }
            else {
                Write-Log "Subscription: $($context.Subscription.Name)" -Level Info
            }
            
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

function Initialize-OutputDirectory {
    <#
    .SYNOPSIS
        Ensures the output directory exists and prepares the CSV file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    
    try {
        $directory = Split-Path -Path $FilePath -Parent
        
        # Create directory if it doesn't exist
        if (-not (Test-Path -Path $directory)) {
            Write-Log "Creating output directory: $directory" -Level Info
            New-Item -Path $directory -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-Log "Directory created successfully" -Level Success
        }
        
        # Clear existing file if present
        if (Test-Path -Path $FilePath) {
            Write-Log "Clearing existing report file: $FilePath" -Level Warning
            Clear-Content -Path $FilePath -ErrorAction Stop
            Write-Log "Existing file cleared" -Level Success
        }
        
        Write-Log "Output will be saved to: $FilePath" -Level Info
        return $true
    }
    catch {
        Write-Log "Failed to initialize output directory: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Get-AzureResourcesWithTags {
    <#
    .SYNOPSIS
        Retrieves all Azure resources using Resource Graph with pagination
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [bool]$UseTenantScope,
        
        [Parameter(Mandatory=$false)]
        [string]$ResourceType,
        
        [Parameter(Mandatory=$false)]
        [int]$PageSize = 1000
    )
    
    try {
        Write-Log "Querying Azure Resource Graph..." -Level Progress
        
        # Build the query
        $query = "resources"
        
        if ($ResourceType) {
            $query += " | where type == '$ResourceType'"
            Write-Log "Filtering by resource type: $ResourceType" -Level Info
        }
        
        # Get total count first
        Write-Log "Getting total resource count..." -Level Progress
        $countQuery = "$query | count"
        
        $queryParams = @{
            Query = $countQuery
            ErrorAction = 'Stop'
        }
        
        if ($UseTenantScope) {
            $queryParams['UseTenantScope'] = $true
        }
        
        $countResult = Search-AzGraph @queryParams
        $totalResources = $countResult.Count_
        
        if ($totalResources -eq 0) {
            Write-Log "No resources found matching the criteria" -Level Warning
            return @()
        }
        
        Write-Log "Total resources to process: $totalResources" -Level Info
        
        # Retrieve resources with pagination
        $allResources = @()
        $skip = 0
        
        while ($skip -lt $totalResources) {
            $remaining = $totalResources - $skip
            $percentComplete = [Math]::Round(($skip / $totalResources) * 100, 2)
            
            Write-Progress -Activity "Retrieving Azure Resources" `
                -Status "Retrieved $skip of $totalResources resources ($percentComplete%)" `
                -PercentComplete $percentComplete
            
            Write-Log "Retrieving resources: $skip to $([Math]::Min($skip + $PageSize, $totalResources)) of $totalResources" -Level Progress
            
            $queryParams = @{
                Query = $query
                First = $PageSize
                ErrorAction = 'Stop'
            }
            
            if ($UseTenantScope) {
                $queryParams['UseTenantScope'] = $true
            }
            
            if ($skip -gt 0) {
                $queryParams['Skip'] = $skip
            }
            
            $pageData = Search-AzGraph @queryParams
            
            if ($pageData) {
                $allResources += $pageData
                Write-Verbose "Retrieved $($pageData.Count) resources in this batch"
            }
            else {
                Write-Log "No data returned for skip value: $skip" -Level Warning
                break
            }
            
            $skip += $PageSize
        }
        
        Write-Progress -Activity "Retrieving Azure Resources" -Completed
        Write-Log "Successfully retrieved $($allResources.Count) resources" -Level Success
        
        return $allResources
    }
    catch {
        Write-Log "Error querying Resource Graph: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Get-UniqueTagNames {
    <#
    .SYNOPSIS
        Extracts all unique tag names from resources
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Resources,
        
        [Parameter(Mandatory=$false)]
        [bool]$ExcludeSystemTags = $true
    )
    
    try {
        Write-Log "Analyzing tag schema..." -Level Progress
        
        $tagNames = @()
        $processedCount = 0
        $resourcesWithTags = 0
        
        foreach ($resource in $Resources) {
            $processedCount++
            
            if ($processedCount % 1000 -eq 0) {
                $percentComplete = [Math]::Round(($processedCount / $Resources.Count) * 100, 2)
                Write-Progress -Activity "Analyzing Tag Schema" `
                    -Status "Processed $processedCount of $($Resources.Count) resources ($percentComplete%)" `
                    -PercentComplete $percentComplete
            }
            
            if ($resource.tags) {
                $resourcesWithTags++
                $resourceTagNames = $resource.tags | Get-Member -MemberType NoteProperty | 
                    Select-Object -ExpandProperty Name
                
                if ($resourceTagNames) {
                    $tagNames += $resourceTagNames
                }
            }
        }
        
        Write-Progress -Activity "Analyzing Tag Schema" -Completed
        
        # Clean and filter tag names
        Write-Log "Processing tag names..." -Level Progress
        
        # Remove special characters that cause issues in PowerShell properties
        $tagNames = $tagNames -replace ":", "" -replace " ", "?"
        
        # Get unique tags
        $uniqueTags = $tagNames | Sort-Object -Unique
        
        # Filter system tags if requested
        if ($ExcludeSystemTags) {
            $filteredTags = $uniqueTags | Where-Object {
                $_ -ne "Name" -and 
                $_ -notlike "*disk*" -and 
                $_ -notlike "*hidden-link*" -and 
                $_ -notlike "*|*"
            }
            
            $excludedCount = $uniqueTags.Count - $filteredTags.Count
            Write-Log "Excluded $excludedCount system-managed tags" -Level Info
            $uniqueTags = $filteredTags
        }
        
        Write-Log "Found $($uniqueTags.Count) unique tags across $resourcesWithTags resources" -Level Success
        
        $script:UniqueTagsFound = $uniqueTags.Count
        $script:ResourcesWithTags = $resourcesWithTags
        
        return $uniqueTags
    }
    catch {
        Write-Log "Error analyzing tags: $($_.Exception.Message)" -Level Error
        throw
    }
}

function New-DynamicResourceClass {
    <#
    .SYNOPSIS
        Creates a dynamic PowerShell class based on discovered tag names
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$TagNames
    )
    
    try {
        Write-Log "Creating dynamic resource class..." -Level Progress
        
        # Start class definition
        $classDefinition = 'class ResourceTagObject {'
        $classDefinition += '[string]${Name};'
        $classDefinition += '[string]${ResourceType};'
        $classDefinition += '[string]${ResourceGroup};'
        $classDefinition += '[string]${Location};'
        $classDefinition += '[string]${SubscriptionId};'
        
        # Add property for each unique tag
        foreach ($tagName in $TagNames) {
            if ($tagName) {
                $classDefinition += "[string]`${$tagName};"
            }
        }
        
        $classDefinition += '}'
        
        Write-Verbose "Class definition: $classDefinition"
        
        # Create the class
        Invoke-Expression $classDefinition -ErrorAction Stop
        
        Write-Log "Dynamic class created with $($TagNames.Count + 5) properties" -Level Success
        return $true
    }
    catch {
        Write-Log "Error creating dynamic class: $($_.Exception.Message)" -Level Error
        throw
    }
}

function ConvertTo-TaggedResourceObject {
    <#
    .SYNOPSIS
        Converts resource data into the dynamic class objects
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Resources,
        
        [Parameter(Mandatory=$false)]
        [bool]$ExcludeSystemTags = $true
    )
    
    try {
        Write-Log "Converting resources to structured objects..." -Level Progress
        
        $results = @()
        $processedCount = 0
        
        foreach ($resource in $Resources) {
            $processedCount++
            
            if ($processedCount % 1000 -eq 0) {
                $percentComplete = [Math]::Round(($processedCount / $Resources.Count) * 100, 2)
                Write-Progress -Activity "Converting Resources" `
                    -Status "Processed $processedCount of $($Resources.Count) resources ($percentComplete%)" `
                    -PercentComplete $percentComplete
            }
            
            # Create new object instance
            $resourceObject = [ResourceTagObject]::new()
            $resourceObject.Name = $resource.name
            $resourceObject.ResourceType = $resource.type
            $resourceObject.ResourceGroup = $resource.resourceGroup
            $resourceObject.Location = $resource.location
            $resourceObject.SubscriptionId = $resource.subscriptionId
            
            # Process tags if they exist
            if ($resource.tags) {
                $resourceTagNames = $resource.tags | Get-Member -MemberType NoteProperty | 
                    Select-Object -ExpandProperty Name
                
                foreach ($tagName in $resourceTagNames) {
                    # Apply same filtering and cleaning as during schema analysis
                    if ($ExcludeSystemTags) {
                        if ($tagName -like "*|*" -or 
                            $tagName -like "*disk*" -or 
                            $tagName -like "*hidden-link*") {
                            continue
                        }
                    }
                    
                    # Clean tag name
                    $cleanTagName = $tagName -replace " ", "?" -replace ":", ""
                    
                    # Get tag value
                    try {
                        $tagValue = $resource.tags.$tagName
                        
                        # Set property value if it exists in our class
                        if ([ResourceTagObject].GetProperties().Name -contains $cleanTagName) {
                            $resourceObject.$cleanTagName = $tagValue
                        }
                    }
                    catch {
                        Write-Verbose "Warning: Could not process tag '$tagName' for resource '$($resource.name)'"
                    }
                }
            }
            
            $results += $resourceObject
        }
        
        Write-Progress -Activity "Converting Resources" -Completed
        Write-Log "Successfully converted $($results.Count) resources" -Level Success
        
        $script:ResourcesProcessed = $results.Count
        
        return $results
    }
    catch {
        Write-Log "Error converting resources: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Export-TagReport {
    <#
    .SYNOPSIS
        Exports the tag data to CSV file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Data,
        
        [Parameter(Mandatory=$true)]
        [string]$OutputPath
    )
    
    try {
        Write-Log "Exporting data to CSV..." -Level Progress
        
        if ($Data.Count -eq 0) {
            Write-Log "No data to export" -Level Warning
            return $false
        }
        
        # Export to CSV
        $Data | Export-Csv -Path $OutputPath -NoTypeInformation -ErrorAction Stop
        
        # Validate file was created
        if (Test-Path -Path $OutputPath) {
            $fileInfo = Get-Item -Path $OutputPath
            $fileSizeMB = [Math]::Round($fileInfo.Length / 1MB, 2)
            
            Write-Log "Successfully exported $($Data.Count) records to CSV" -Level Success
            Write-Log "File size: $fileSizeMB MB" -Level Info
            Write-Log "File location: $OutputPath" -Level Info
            
            return $true
        }
        else {
            Write-Log "Export completed but file not found at expected location" -Level Warning
            return $false
        }
    }
    catch {
        Write-Log "Error exporting to CSV: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Show-ExecutionSummary {
    <#
    .SYNOPSIS
        Displays comprehensive execution summary
    #>
    [CmdletBinding()]
    param()
    
    $endTime = Get-Date
    $duration = $endTime - $script:StartTime
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "EXECUTION SUMMARY" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Start Time:              $($script:StartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor White
    Write-Host "End Time:                $($endTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor White
    Write-Host "Duration:                $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor White
    Write-Host "Resources Processed:     $($script:ResourcesProcessed)" -ForegroundColor Green
    Write-Host "Resources with Tags:     $($script:ResourcesWithTags)" -ForegroundColor Green
    Write-Host "Unique Tags Found:       $($script:UniqueTagsFound)" -ForegroundColor Green
    Write-Host "Output File:             $OutputPath" -ForegroundColor White
    Write-Host "========================================`n" -ForegroundColor Cyan
}

#endregion

#region Main Execution

try {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Azure Resource Tag Inventory Tool" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    # Step 1: Validate modules
    if (-not (Test-RequiredModules)) {
        Write-Log "Cannot proceed without required modules. Exiting." -Level Error
        exit 1
    }
    
    # Step 2: Test Azure connection
    if (-not (Test-AzureConnection)) {
        Write-Log "Cannot proceed without Azure connection. Exiting." -Level Error
        exit 1
    }
    
    # Step 3: Initialize output directory
    if (-not (Initialize-OutputDirectory -FilePath $OutputPath)) {
        Write-Log "Cannot proceed without valid output path. Exiting." -Level Error
        exit 1
    }
    
    # Step 4: Retrieve all resources
    $resources = Get-AzureResourcesWithTags -UseTenantScope $UseTenantScope -ResourceType $ResourceType -PageSize $PageSize
    
    if ($resources.Count -eq 0) {
        Write-Log "No resources found. Nothing to export." -Level Warning
        exit 0
    }
    
    # Step 5: Analyze tag schema
    $uniqueTagNames = Get-UniqueTagNames -Resources $resources -ExcludeSystemTags $ExcludeSystemTags
    
    if ($uniqueTagNames.Count -eq 0) {
        Write-Log "No tags found on any resources. Exporting basic resource information only." -Level Warning
    }
    
    # Step 6: Create dynamic class
    New-DynamicResourceClass -TagNames $uniqueTagNames | Out-Null
    
    # Step 7: Convert resources to objects
    $taggedResources = ConvertTo-TaggedResourceObject -Resources $resources -ExcludeSystemTags $ExcludeSystemTags
    
    # Step 8: Export to CSV
    $exportSuccess = Export-TagReport -Data $taggedResources -OutputPath $OutputPath
    
    if (-not $exportSuccess) {
        Write-Log "Export failed. Please check error messages above." -Level Error
        exit 1
    }
    
    # Step 9: Show summary
    Show-ExecutionSummary
    
    Write-Log "Tag inventory completed successfully!" -Level Success
}
catch {
    Write-Log "Critical error occurred: $($_.Exception.Message)" -Level Error
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level Error
    Show-ExecutionSummary
    exit 1
}
finally {
    # Cleanup progress bars
    Write-Progress -Activity "Retrieving Azure Resources" -Completed -ErrorAction SilentlyContinue
    Write-Progress -Activity "Analyzing Tag Schema" -Completed -ErrorAction SilentlyContinue
    Write-Progress -Activity "Converting Resources" -Completed -ErrorAction SilentlyContinue
}

#endregion