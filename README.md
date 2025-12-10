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

*(Add description based on the TagFix.ps1 functionality)*

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

**Author**: Azure Infrastructure Team  
**Repository**: https://github.com/gplima89/AzureTagManagementAndFix  
**Last Updated**: December 10, 2025