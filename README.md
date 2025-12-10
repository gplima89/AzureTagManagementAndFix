# Azure Tag Management and Fix

A collection of PowerShell scripts for managing, analyzing, and fixing Azure resource tags across your Azure environment.

## 📋 Overview

This repository contains enterprise-grade PowerShell tools designed to help Azure administrators maintain consistent tagging across their Azure resources. The scripts leverage Azure Resource Graph API for efficient querying and support both single-subscription and tenant-wide operations.

## 🎯 Objectives

- **Inventory Management**: Export comprehensive tag inventories across all Azure resources
- **Tag Analysis**: Identify resources with missing or inconsistent tags
- **Compliance**: Ensure resources meet organizational tagging standards
- **Reporting**: Generate detailed CSV reports for auditing and analysis
- **Automation**: Enable automated tag management workflows

## 🚀 Scripts

### TagWorkShop.ps1
**Azure Resource Tag Inventory and Export Tool**

Collects all Azure resources and their tags using Azure Resource Graph API, then exports the data to a CSV file with dynamic columns for each unique tag name.

#### Key Features:
- ✅ Tenant-wide or subscription-scoped queries
- ✅ Dynamic column generation based on discovered tags
- ✅ Automatic pagination for large datasets (handles 1000+ resources)
- ✅ System tag filtering (excludes disk-related, hidden-link tags)
- ✅ Resource type filtering
- ✅ Comprehensive logging and progress tracking
- ✅ Performance optimized using Azure Resource Graph

#### Parameters:
- **OutputPath**: CSV file path (Default: `C:\temp\TagsReport2.csv`)
- **UseTenantScope**: Query all subscriptions in tenant (Default: `$true`)
- **ResourceType**: Filter by specific resource type (Optional)
- **PageSize**: Resources per page (Default: 1000, Max: 1000)
- **ExcludeSystemTags**: Exclude system-managed tags (Default: `$true`)

#### Examples:
```powershell
# Basic usage - export all resources across tenant
.\TagWorkShop.ps1

# Custom output path and specific resource type
.\TagWorkShop.ps1 -OutputPath "D:\Reports\AzureTags.csv" -ResourceType "Microsoft.Compute/virtualMachines"

# Single subscription scope
.\TagWorkShop.ps1 -UseTenantScope:$false

# Include system tags
.\TagWorkShop.ps1 -ExcludeSystemTags:$false
```

### TagFix.ps1
**Azure Resource Tag Management and Remediation Tool**

Replaces a specific tag name with a new tag name across Azure resources. This script is designed for tag standardization projects and includes comprehensive backup and rollback capabilities to ensure safe execution.

#### Key Features:
- ✅ Safe tag replacement with automatic backup
- ✅ Pre-execution validation and confirmation prompts
- ✅ Real-time verification after each tag update
- ✅ Comprehensive CSV backup for rollback scenarios
- ✅ Resource type filtering (default: Virtual Machines)
- ✅ Duplicate tag detection and conflict resolution
- ✅ Detailed execution summary and statistics
- ✅ Automatic rollback support via backup files

#### Parameters:
- **TagToReplace**: The existing tag name to replace (Required)
- **TagNewName**: The new tag name (Required)
- **ResourceType**: Resource type filter (Default: `Microsoft.Compute/virtualMachines`)
- **SubscriptionId**: Target specific subscription (Optional)

#### Examples:
```powershell
# Interactive mode - prompts for parameters
.\TagFix.ps1

# Replace 'Environment' tag with 'Env' across all VMs
.\TagFix.ps1 -TagToReplace "Environment" -TagNewName "Env"

# Replace tag for specific resource type
.\TagFix.ps1 -TagToReplace "Owner" -TagNewName "ResourceOwner" -ResourceType "Microsoft.Storage/storageAccounts"

# Target specific subscription
.\TagFix.ps1 -TagToReplace "CostCenter" -TagNewName "Cost-Center" -SubscriptionId "your-subscription-id"

# Use with -WhatIf for testing (shows what would happen)
.\TagFix.ps1 -TagToReplace "Dept" -TagNewName "Department" -WhatIf
```

## 🛠️ Setup

### Prerequisites

1. **PowerShell 7.0 or higher** (Recommended)
   ```powershell
   $PSVersionTable.PSVersion
   ```

2. **Azure PowerShell Modules**
   - Az.Accounts (v2.0.0 or higher)
   - Az.ResourceGraph (v0.7.0 or higher)

### Installation

1. **Clone the repository**
   ```powershell
   git clone https://github.com/gplima89/AzureTagManagementAndFix.git
   cd AzureTagManagementAndFix
   ```

2. **Install required Azure modules**
   ```powershell
   # Install Az.Accounts module
   Install-Module -Name Az.Accounts -Force -AllowClobber
   
   # Install Az.ResourceGraph module
   Install-Module -Name Az.ResourceGraph -Force -AllowClobber
   ```

3. **Verify module installation**
   ```powershell
   Get-Module -ListAvailable -Name Az.Accounts, Az.ResourceGraph
   ```

### Azure Authentication

1. **Connect to Azure**
   ```powershell
   Connect-AzAccount
   ```

2. **For tenant-wide queries, ensure you have:**
   - Reader permissions across all subscriptions
   - Or appropriate RBAC role at Management Group/Tenant level

3. **Verify your context**
   ```powershell
   Get-AzContext
   ```

## 📖 How to Run

### Running TagWorkShop.ps1

1. **Basic execution** (uses default settings):
   ```powershell
   .\TagWorkShop.ps1
   ```
   This will:
   - Query all subscriptions in your tenant
   - Export results to `C:\temp\TagsReport2.csv`
   - Exclude system-managed tags
   - Show progress and statistics

2. **Custom output location**:
   ```powershell
   .\TagWorkShop.ps1 -OutputPath "C:\Reports\MyTagInventory.csv"
   ```

3. **Filter by resource type**:
   ```powershell
   # Only Virtual Machines
   .\TagWorkShop.ps1 -ResourceType "Microsoft.Compute/virtualMachines"
   
   # Only Storage Accounts
   .\TagWorkShop.ps1 -ResourceType "Microsoft.Storage/storageAccounts"
   ```

4. **Single subscription mode**:
   ```powershell
   # First, set your subscription context
   Set-AzContext -SubscriptionId "your-subscription-id"
   
   # Run the script
   .\TagWorkShop.ps1 -UseTenantScope:$false
   ```

5. **Enable verbose logging**:
   ```powershell
   .\TagWorkShop.ps1 -Verbose
   ```

### Understanding the Output

The script generates a CSV file with the following structure:
- **Name**: Resource name
- **ResourceType**: Azure resource type
- **ResourceGroup**: Resource group name
- **Location**: Azure region
- **SubscriptionId**: Subscription ID
- **Dynamic Tag Columns**: One column per unique tag found in your environment

Example output:
```
Name,ResourceType,ResourceGroup,Location,SubscriptionId,Environment,Owner,CostCenter,Application
vm-prod-01,Microsoft.Compute/virtualMachines,rg-production,eastus,abc123...,Production,john@contoso.com,IT-001,WebApp
```

### Running TagFix.ps1

#### Pre-Execution Checklist:
✅ **Test in non-production first**  
✅ **Verify current tag names with TagWorkShop.ps1**  
✅ **Ensure you have Contributor or Tag Contributor role**  
✅ **Review the backup location has sufficient space**  
✅ **Plan for a maintenance window if updating critical resources**

#### Step-by-Step Execution:

1. **Test Mode - See what will happen** (Recommended first step):
   ```powershell
   # Dry run to preview changes
   .\TagFix.ps1 -TagToReplace "Environment" -TagNewName "Env" -WhatIf
   ```

2. **Interactive Mode** (Safest for first-time users):
   ```powershell
   # Script will prompt for all parameters
   .\TagFix.ps1
   ```
   The script will:
   - Prompt for old tag name
   - Prompt for new tag name
   - Show you all affected resources
   - Ask for confirmation before proceeding
   - Create automatic backup
   - Process each resource with verification

3. **Direct Execution** (For experienced users):
   ```powershell
   # Replace 'Owner' with 'ResourceOwner' on all VMs
   .\TagFix.ps1 -TagToReplace "Owner" -TagNewName "ResourceOwner"
   ```

4. **Specific Resource Type**:
   ```powershell
   # Replace tags only on Storage Accounts
   .\TagFix.ps1 -TagToReplace "Dept" -TagNewName "Department" `
                -ResourceType "Microsoft.Storage/storageAccounts"
   ```

5. **Target Specific Subscription**:
   ```powershell
   # Work in a specific subscription
   .\TagFix.ps1 -TagToReplace "CostCenter" -TagNewName "Cost-Center" `
                -SubscriptionId "12345678-1234-1234-1234-123456789012"
   ```

#### Understanding the Execution Flow:

```
1. Connection Check → Validates Azure authentication
2. Parameter Validation → Ensures tag names are different
3. Resource Discovery → Finds all resources with the old tag
4. Preview & Confirmation → Shows affected resources, waits for approval
5. Backup Creation → Creates CSV backup before ANY changes
6. Tag Replacement → Processes each resource individually
   ├─ Validates old tag exists
   ├─ Checks for tag conflicts
   ├─ Removes old tag
   ├─ Adds new tag with same value
   └─ Verifies the change
7. Summary Report → Shows success/failure/skipped counts
```

#### Backup File Details:

The script automatically creates a backup CSV file with the naming pattern:
```
TagReplacement_<OldTag>_to_<NewTag>_<timestamp>.csv
```

Example: `TagReplacement_Environment_to_Env_20251210_143052.csv`

**Backup file contains:**
- Timestamp of backup
- Resource Name, ID, Type, Location
- Resource Group Name
- Old Tag Name and Value
- New Tag Name
- All existing tags on the resource
- Operation status

**Sample backup file:**
```csv
Timestamp,Name,ResourceGroupName,ResourceId,ResourceType,Location,OldTagName,NewTagName,TagValue,AllTags,Status
2025-12-10 14:30:52,vm-prod-01,rg-production,/subscriptions/.../vm-prod-01,Microsoft.Compute/virtualMachines,eastus,Environment,Env,Production,Environment; Owner; CostCenter,Pending
```

## 🔄 Rollback Procedures

### When to Rollback:
- Incorrect tag name was used
- Wrong resources were affected
- Tag values were not preserved correctly
- Business requirement changed during execution

### Method 1: Manual Rollback Using Azure Portal
1. Open the backup CSV file
2. Filter for affected resources
3. Manually revert tags in Azure Portal using the backup data

### Method 2: Automated Rollback with PowerShell Script

Create a rollback script using the backup file:

```powershell
# Rollback script - Save as TagFix-Rollback.ps1
param(
    [Parameter(Mandatory=$true)]
    [string]$BackupFile
)

# Import backup data
$backupData = Import-Csv -Path $BackupFile

Write-Host "Found $($backupData.Count) resources in backup file" -ForegroundColor Cyan

foreach ($item in $backupData) {
    try {
        Write-Host "Rolling back: $($item.Name)" -ForegroundColor Yellow
        
        # Get current resource
        $resource = Get-AzResource -ResourceId $item.ResourceId -ErrorAction Stop
        
        # Clone current tags
        $tags = @{}
        if ($resource.Tags) {
            foreach ($key in $resource.Tags.Keys) {
                $tags[$key] = $resource.Tags[$key]
            }
        }
        
        # Remove new tag if present
        if ($tags.ContainsKey($item.NewTagName)) {
            $tags.Remove($item.NewTagName)
            Write-Host "  Removed tag: $($item.NewTagName)" -ForegroundColor Gray
        }
        
        # Restore old tag
        $tags[$item.OldTagName] = $item.TagValue
        Write-Host "  Restored tag: $($item.OldTagName) = $($item.TagValue)" -ForegroundColor Gray
        
        # Apply tags
        Update-AzTag -ResourceId $item.ResourceId -Tag $tags -Operation Replace -ErrorAction Stop
        Write-Host "  ✓ Successfully rolled back: $($item.Name)" -ForegroundColor Green
    }
    catch {
        Write-Host "  ✗ Failed to rollback: $($item.Name) - $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nRollback operation completed!" -ForegroundColor Cyan
```

**To execute rollback:**
```powershell
.\TagFix-Rollback.ps1 -BackupFile ".\TagReplacement_Environment_to_Env_20251210_143052.csv"
```

### Method 3: Selective Rollback
```powershell
# Rollback only specific resources
$backupFile = ".\TagReplacement_Environment_to_Env_20251210_143052.csv"
$backup = Import-Csv -Path $backupFile

# Filter for specific resource group or name pattern
$resourcestoRollback = $backup | Where-Object { $_.ResourceGroupName -eq "rg-production" }

foreach ($item in $resourcestoRollback) {
    $resource = Get-AzResource -ResourceId $item.ResourceId
    $tags = $resource.Tags
    $tags.Remove($item.NewTagName)
    $tags[$item.OldTagName] = $item.TagValue
    Update-AzTag -ResourceId $item.ResourceId -Tag $tags -Operation Replace
}
```

### Best Practices for Rollback:
1. **Keep backup files for at least 30 days** after tag changes
2. **Test rollback script** in non-production environment first
3. **Document the rollback** in your change management system
4. **Verify data integrity** after rollback using TagWorkShop.ps1
5. **Coordinate with team** before executing rollback on production resources

## 📊 Use Cases

### 1. Tag Compliance Audit
```powershell
# Export all resources and analyze which ones are missing required tags
.\TagWorkShop.ps1 -OutputPath "C:\Audit\TagCompliance.csv"
```

### 2. Cost Center Analysis
```powershell
# Export and group by cost center tags for billing
.\TagWorkShop.ps1 -OutputPath "C:\Finance\CostCenterTags.csv"
```

### 3. Environment Inventory
```powershell
# Filter production VMs only
.\TagWorkShop.ps1 -ResourceType "Microsoft.Compute/virtualMachines" -OutputPath "C:\Inventory\ProdVMs.csv"
```

### 4. Tag Migration Planning
```powershell
# Export current state before tag standardization
.\TagWorkShop.ps1 -ExcludeSystemTags:$false -OutputPath "C:\Migration\BeforeState.csv"
```

## ⚡ Performance Notes

- Uses Azure Resource Graph for efficient querying (much faster than `Get-AzResource`)
- Handles pagination automatically for large tenants
- Processes 1000 resources per page by default
- Dynamic class creation allows flexible tag schema
- Typical execution time: 2-5 minutes for 10,000 resources

## 🔒 Required Permissions

### For TagWorkShop.ps1:
- **Reader** role at the desired scope (Subscription/Management Group/Tenant)
- No write permissions required

### For TagFix.ps1:
- **Contributor** or **Tag Contributor** role at the desired scope
- Permissions to modify resource tags

## 🧪 Testing TagFix.ps1

### Testing Strategy:

#### Phase 1: Pre-Production Testing
```powershell
# Step 1: Create a test resource group with sample VMs
New-AzResourceGroup -Name "rg-tag-testing" -Location "eastus"

# Step 2: Create test VMs with tags
$testTags = @{
    "Environment" = "Test"
    "Owner" = "test-user@contoso.com"
    "CostCenter" = "IT-001"
}

# Create a test VM (simplified - adjust as needed)
New-AzVM -ResourceGroupName "rg-tag-testing" `
         -Name "vm-test-01" `
         -Location "eastus" `
         -Tag $testTags `
         -Size "Standard_B2s"

# Step 3: Verify tags are present
Get-AzResource -ResourceGroupName "rg-tag-testing" | Select-Object Name, Tags
```

#### Phase 2: Test Tag Replacement
```powershell
# Test the tag replacement on test resources
.\TagFix.ps1 -TagToReplace "Environment" -TagNewName "Env" `
             -ResourceType "Microsoft.Compute/virtualMachines"
```

#### Phase 3: Verify Results
```powershell
# Check if tags were replaced correctly
$testVM = Get-AzVM -ResourceGroupName "rg-tag-testing" -Name "vm-test-01"

# Verify new tag exists
if ($testVM.Tags.ContainsKey("Env")) {
    Write-Host "✓ New tag 'Env' found" -ForegroundColor Green
}

# Verify old tag is removed
if (-not $testVM.Tags.ContainsKey("Environment")) {
    Write-Host "✓ Old tag 'Environment' removed" -ForegroundColor Green
}

# Verify tag value preserved
if ($testVM.Tags["Env"] -eq "Test") {
    Write-Host "✓ Tag value preserved correctly" -ForegroundColor Green
}
```

#### Phase 4: Test Rollback
```powershell
# Test the rollback procedure with your backup file
.\TagFix-Rollback.ps1 -BackupFile ".\TagReplacement_Environment_to_Env_*.csv"

# Verify rollback worked
$testVM = Get-AzVM -ResourceGroupName "rg-tag-testing" -Name "vm-test-01"
$testVM.Tags  # Should show original "Environment" tag
```

#### Phase 5: Edge Case Testing
```powershell
# Test 1: Tag that doesn't exist
.\TagFix.ps1 -TagToReplace "NonExistentTag" -TagNewName "NewTag"
# Expected: Script should report no resources found

# Test 2: Duplicate tag scenario
# Manually add both old and new tags to a resource first
$vm = Get-AzVM -ResourceGroupName "rg-tag-testing" -Name "vm-test-01"
$vm.Tags["Environment"] = "Test"
$vm.Tags["Env"] = "Production"  # Different value
Update-AzTag -ResourceId $vm.Id -Tag $vm.Tags -Operation Replace

# Run script - should skip this resource
.\TagFix.ps1 -TagToReplace "Environment" -TagNewName "Env"
# Expected: Resource skipped with warning about conflicting values

# Test 3: Same tag name
.\TagFix.ps1 -TagToReplace "Environment" -TagNewName "Environment"
# Expected: Script exits with "nothing to do" message
```

### Testing Checklist:
- [ ] Test in isolated resource group first
- [ ] Verify backup file is created
- [ ] Confirm tag values are preserved
- [ ] Test rollback procedure works
- [ ] Validate edge cases (non-existent tags, duplicates)
- [ ] Check execution summary is accurate
- [ ] Verify no unintended resources were modified
- [ ] Test with different resource types
- [ ] Confirm script handles errors gracefully

## 🐛 Troubleshooting

### Module Not Found
```powershell
# Reinstall modules
Install-Module -Name Az.Accounts -Force
Install-Module -Name Az.ResourceGraph -Force
```

### Authentication Issues
```powershell
# Clear and reconnect
Disconnect-AzAccount
Connect-AzAccount
```

### Large Dataset Timeouts
- The script automatically handles pagination
- For very large tenants (100K+ resources), consider filtering by resource type

### Permission Errors
- Verify RBAC assignments: `Get-AzRoleAssignment -SignInName your-email@domain.com`
- Ensure Reader role at appropriate scope

### TagFix.ps1 Specific Issues

#### "No resources found with tag" Error
```powershell
# Verify the tag actually exists
Get-AzResource -TagName "YourTagName"

# Check if you're in the right subscription
Get-AzContext
Set-AzContext -SubscriptionId "correct-subscription-id"
```

#### Tags Not Updating
```powershell
# Check if you have tag modification permissions
Get-AzRoleAssignment -SignInName your-email@domain.com | Where-Object {
    $_.RoleDefinitionName -like "*Contributor*" -or 
    $_.RoleDefinitionName -like "*Tag*"
}

# Try updating a single tag manually to test permissions
$resource = Get-AzResource -Name "test-resource"
Update-AzTag -ResourceId $resource.ResourceId -Tag @{"TestTag"="TestValue"} -Operation Merge
```

#### Backup File Not Created
```powershell
# Check current directory permissions
Test-Path -Path "." -PathType Container

# Specify full path for backup
# Modify line 394 in TagFix.ps1 to use full path:
$logFileName = "C:\Backups\TagReplacement_$($TagToReplace)_to_$($TagNewName)_$currentDate.csv"
```

#### Script Hangs or Times Out
- Reduce batch size by filtering to specific resource types
- Process one resource group at a time
- Check Azure service health for API throttling issues

#### Rollback Script Fails
```powershell
# Verify backup file format
Import-Csv -Path "your-backup.csv" | Select-Object -First 1

# Check if resources still exist
$backup = Import-Csv -Path "your-backup.csv"
foreach ($item in $backup) {
    $exists = Get-AzResource -ResourceId $item.ResourceId -ErrorAction SilentlyContinue
    if (-not $exists) {
        Write-Host "Resource not found: $($item.Name)" -ForegroundColor Yellow
    }
}
```

## 📝 Version History

- **v2.0** (December 10, 2025)
  - Enhanced error handling
  - Dynamic class creation for flexible schema
  - Improved pagination support
  - Added system tag filtering
  - Performance optimizations

## 👥 Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## 📄 License

This project is provided as-is for Azure administrators to manage their environments.

## 📧 Support

For issues or questions, please open an issue in the GitHub repository.

---

**Author**: Guil Lima - Microsoft Canada - CSA  
**Contact**: guillima@microsoft.com  
**Repository**: https://github.com/gplima89/AzureTagManagementAndFix  
**Last Updated**: December 10, 2025