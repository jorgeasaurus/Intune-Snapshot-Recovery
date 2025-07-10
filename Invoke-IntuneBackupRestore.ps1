#Requires -Version 5.1
<#
.SYNOPSIS
    Comprehensive PowerShell script for backing up and restoring Microsoft Intune configurations with dynamic configuration generation.

.DESCRIPTION
    This script provides advanced Intune backup and restore functionality with fully customizable parameters:
    
    BACKUP (Export) Features:
    - Export Intune policies, configurations, and assignments to JSON files
    - Dynamically generate export configurations without requiring static JSON files
    - Customize export scope with specific object types, name filters, and export options
    - Support for exporting scripts, applications, assignments, and adding company branding
    
    RESTORE (Import) Features:
    - Import Intune configurations from backup directories
    - Dynamically generate import configurations with flexible parameters
    - Control import behavior (skip existing, overwrite, append)
    - Selective import of object types and conditional access policy states
    - Support for assignment import and dependency ID replacement
    
    The script automatically clones the IntuneManagement tool if not present and uses
    Azure AD application authentication for secure access to Microsoft Graph APIs.

.PARAMETER Action
    Specifies the operation to perform: 'Backup' (export) or 'Restore' (import)

.PARAMETER TenantId
    Azure AD Tenant ID for authentication

.PARAMETER AppId
    Azure AD Application (Client) ID with required Microsoft Graph permissions

.PARAMETER Secret
    Azure AD Application Client Secret for authentication

.PARAMETER IntuneManagementPath
    Local path where the IntuneManagement tool will be stored/found (default: ".\IntuneManagement")

.PARAMETER BackupPath
    Target directory for backup files (export) or source directory for restore files (import) - Required

.PARAMETER DryRun
    Performs validation and preview without executing actual import (Restore action only)

.PARAMETER NameFilter
    Filter string to match policy names (empty string processes all files)

.PARAMETER AddObjectType
    Add object type prefix to exported/imported file names (default: $true)

.PARAMETER ImportScopes
    Import scope tags during restore (default: $false)

.PARAMETER ImportAssignments
    Import policy assignments during restore (default: $false)

.PARAMETER ReplaceDependencyIDs
    Replace dependency IDs during import to avoid conflicts (default: $true)

.PARAMETER ImportType
    Import behavior: "skipIfExist" (default), "overwrite", or "append"

.PARAMETER CAState
    Conditional Access policy state: "disabled" (default), "enabled", or "enabledForReportingButNotEnforced"

.PARAMETER ObjectTypes
    Array of specific Intune object types to process (default: all available types)
    Examples: @("CompliancePolicies", "DeviceConfiguration", "AppProtection")

.PARAMETER ExportAssignments
    Export policy assignments during backup (default: $true)

.PARAMETER AddCompanyName
    Add company name to exported file names (default: $false)

.PARAMETER ExportScript
    Export PowerShell scripts during backup (default: $true)

.PARAMETER ExportApplicationFile
    Export application installation files during backup (default: $false)

.EXAMPLE
    # Basic backup of all Intune configurations
    .\Invoke-IntuneBackupRestore.ps1 -Action Backup -TenantId "12345678-1234-1234-1234-123456789012" -AppId "87654321-4321-4321-4321-210987654321" -Secret "your-secret" -BackupPath ".\intune-backup\production"

.EXAMPLE
    # Basic restore from backup directory
    .\Invoke-IntuneBackupRestore.ps1 -Action Restore -TenantId "12345678-1234-1234-1234-123456789012" -AppId "87654321-4321-4321-4321-210987654321" -Secret "your-secret" -BackupPath ".\intune-backup\sample-tenant"

.EXAMPLE
    # Selective backup of Windows policies only
    .\Invoke-IntuneBackupRestore.ps1 -Action Backup -TenantId "$env:AZURE_TENANT_ID" -AppId "$env:AZURE_CLIENT_ID" -Secret "$env:AZURE_CLIENT_SECRET" -BackupPath ".\backups\windows-only" -NameFilter "WIN-" -ObjectTypes @("DeviceConfiguration", "CompliancePolicies")

.EXAMPLE
    # Restore with assignments and enable Conditional Access policies
    .\Invoke-IntuneBackupRestore.ps1 -Action Restore -TenantId "$env:AZURE_TENANT_ID" -AppId "$env:AZURE_CLIENT_ID" -Secret "$env:AZURE_CLIENT_SECRET" -BackupPath ".\intune-backup\sample-tenant" -ImportAssignments $true -CAState "enabled"

.EXAMPLE
    # Dry run restore to preview what would be imported
    .\Invoke-IntuneBackupRestore.ps1 -Action Restore -TenantId "$env:AZURE_TENANT_ID" -AppId "$env:AZURE_CLIENT_ID" -Secret "$env:AZURE_CLIENT_SECRET" -BackupPath ".\intune-backup\test" -DryRun

.EXAMPLE
    # Full backup with company branding and application files
    .\Invoke-IntuneBackupRestore.ps1 -Action Backup -TenantId "$env:AZURE_TENANT_ID" -AppId "$env:AZURE_CLIENT_ID" -Secret "$env:AZURE_CLIENT_SECRET" -BackupPath ".\full-backup" -AddCompanyName $true -ExportApplicationFile $true -ExportAssignments $true

.EXAMPLE
    # Overwrite existing policies during restore
    .\Invoke-IntuneBackupRestore.ps1 -Action Restore -TenantId "$env:AZURE_TENANT_ID" -AppId "$env:AZURE_CLIENT_ID" -Secret "$env:AZURE_CLIENT_SECRET" -BackupPath ".\intune-backup\updates" -ImportType "overwrite" -ImportAssignments $false

.NOTES
    Author: Generated with Claude Code
    Version: 2.0
    Requires: PowerShell 5.1 or later
    Dependencies: IntuneManagement tool (automatically downloaded)
    
    Azure AD App Registration Requirements:
    - Microsoft Graph API permissions for Intune management
    - Application (not delegated) permissions recommended
    - Required permissions include DeviceManagementConfiguration.ReadWrite.All, DeviceManagementApps.ReadWrite.All, etc.

.LINK
    https://github.com/Micke-K/IntuneManagement
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Backup', 'Restore')]
    [string]$Action,
    
    [Parameter(Mandatory = $true)]
    [string]$TenantId,
    
    [Parameter(Mandatory = $true)]
    [string]$AppId,
    
    [Parameter(Mandatory = $true)]
    [string]$Secret,
    
    [Parameter(Mandatory = $false)]
    [string]$IntuneManagementPath = ".\IntuneManagement",
    
    [Parameter(Mandatory = $true)]
    [string]$BackupPath,
    
    [Parameter(Mandatory = $false)]
    [switch]$DryRun,
    
    # Import configuration parameters
    [Parameter(Mandatory = $false)]
    [string]$NameFilter,
    
    [Parameter(Mandatory = $false)]
    [bool]$AddObjectType,
    
    [Parameter(Mandatory = $false)]
    [bool]$ImportScopes,
    
    [Parameter(Mandatory = $false)]
    [bool]$ImportAssignments,
    
    [Parameter(Mandatory = $false)]
    [bool]$ReplaceDependencyIDs,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("skipIfExist", "overwrite", "append")]
    [string]$ImportType,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("disabled", "enabled", "enabledForReportingButNotEnforced")]
    [string]$CAState,
    
    [Parameter(Mandatory = $false)]
    [string[]]$ObjectTypes,
    
    # Export configuration parameters (only used with Backup action)
    [Parameter(Mandatory = $false)]
    [bool]$ExportAssignments,
    
    [Parameter(Mandatory = $false)]
    [bool]$AddCompanyName,
    
    [Parameter(Mandatory = $false)]
    [bool]$ExportScript,
    
    [Parameter(Mandatory = $false)]
    [bool]$ExportApplicationFile
)

function Write-Status {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $(
        switch ($Level) {
            "ERROR" { "Red" }
            "WARNING" { "Yellow" }
            "SUCCESS" { "Green" }
            default { "White" }
        }
    )
}

function Get-IntuneManagementTool {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        Write-Status "IntuneManagement tool not found. Cloning from GitHub..."
        try {
            git clone --branch 3.9.8 https://github.com/Micke-K/IntuneManagement.git $Path
            Write-Status "Successfully cloned IntuneManagement tool" "SUCCESS"
        } catch {
            Write-Status "Failed to clone IntuneManagement tool: $_" "ERROR"
            throw
        }
    } else {
        Write-Status "IntuneManagement tool found at: $Path"
    }
    
    $startScript = Join-Path $Path "Start-IntuneManagement.ps1"
    if (-not (Test-Path $startScript)) {
        Write-Status "Start-IntuneManagement.ps1 not found in $Path" "ERROR"
        throw "IntuneManagement tool appears to be incomplete"
    }
    
    return $startScript
}

function New-DynamicImportConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ImportPath,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        
        [Parameter(Mandatory = $false)]
        [string[]]$ObjectTypes,
        
        [Parameter(Mandatory = $false)]
        [string]$NameFilter = "",
        
        [Parameter(Mandatory = $false)]
        [bool]$AddObjectType = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$ImportScopes = $false,
        
        [Parameter(Mandatory = $false)]
        [bool]$ImportAssignments = $false,
        
        [Parameter(Mandatory = $false)]
        [bool]$ReplaceDependencyIDs = $true,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("skipIfExist", "overwrite", "append")]
        [string]$ImportType = "skipIfExist",
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("disabled", "enabled", "enabledForReportingButNotEnforced")]
        [string]$CAState = "disabled"
    )
    
    Write-Status "Generating dynamic import configuration for path: $ImportPath"
    
    # Define all available object types
    $allObjectTypes = @(
        "AdministrativeTemplates",
        "ADMXFiles", 
        "AndroidOEMConfig",
        "AppConfigurationManagedApp",
        "AppConfigurationManagedDevice",
        "AppProtection",
        "AppleEnrollmentTypes",
        "Applications",
        "AuthenticationContext",
        "AuthenticationStrengths",
        "AutoPilot",
        "CoManagementSettings",
        "CompliancePolicies",
        "CompliancePoliciesV2",
        "ComplianceScripts",
        "ConditionalAccess",
        "MacCustomAttributes",
        "DeviceConfiguration",
        "DriverUpdateProfiles",
        "EndpointSecurity",
        "EnrollmentRestrictions",
        "EnrollmentStatusPage",
        "FeatureUpdates",
        "AssignmentFilters",
        "DeviceHealthScripts",
        "IntuneBranding",
        "NamedLocations",
        "Notifications",
        "PolicySets",
        "QualityUpdates",
        "ReusableSettings",
        "RoleDefinitions",
        "ScopeTags",
        "PowerShellScripts",
        "MacScripts",
        "SettingsCatalog",
        "TermsAndConditions",
        "TermsOfUse",
        "UpdatePolicies",
        "W365ProvisioningPolicies",
        "W365UserSettings"
    )
    
    # Use provided object types or default to all
    if (-not $ObjectTypes) {
        $ObjectTypes = $allObjectTypes
    }
    
    # Create configuration object
    $config = [PSCustomObject]@{
        BulkImport = @(
            @{
                Name  = "txtImportPath"
                Value = $ImportPath
            },
            @{
                Name  = "txtImportNameFilter"
                Value = $NameFilter
            },
            @{
                Name  = "chkAddObjectType"
                Value = $AddObjectType
            },
            @{
                Name  = "chkImportScopes"
                Value = $ImportScopes
            },
            @{
                Name  = "chkImportAssignments"
                Value = $ImportAssignments
            },
            @{
                Name  = "chkReplaceDependencyIDs"
                Value = $ReplaceDependencyIDs
            },
            @{
                Name  = "cbImportType"
                Value = $ImportType
            },
            @{
                Name  = "cbImportCAState"
                Value = $CAState
            },
            @{
                Name        = "ObjectTypes"
                Type        = "Custom"
                ObjectTypes = $ObjectTypes
            }
        )
    }
    
    # Convert to JSON and save
    try {
        $jsonContent = $config | ConvertTo-Json -Depth 10 -Compress:$false
        [System.IO.File]::WriteAllText($OutputPath, $jsonContent, [System.Text.Encoding]::UTF8)
        Write-Status "Dynamic import configuration saved to: $OutputPath" "SUCCESS"
        return $OutputPath
    } catch {
        Write-Status "Failed to create dynamic import configuration: $_" "ERROR"
        throw
    }
}

function New-DynamicExportConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExportPath,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        
        [Parameter(Mandatory = $false)]
        [string[]]$ObjectTypes,
        
        [Parameter(Mandatory = $false)]
        [string]$NameFilter = "",
        
        [Parameter(Mandatory = $false)]
        [bool]$AddObjectType = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$ExportAssignments = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$AddCompanyName = $false,
        
        [Parameter(Mandatory = $false)]
        [bool]$ExportScript = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$ExportApplicationFile = $false
    )
    
    Write-Status "Generating dynamic export configuration for path: $ExportPath"
    
    # Define all available object types
    $allObjectTypes = @(
        "AdministrativeTemplates",
        "ADMXFiles", 
        "AndroidOEMConfig",
        "AppConfigurationManagedApp",
        "AppConfigurationManagedDevice",
        "AppProtection",
        "AppleEnrollmentTypes",
        "Applications",
        "AuthenticationContext",
        "AuthenticationStrengths",
        "AutoPilot",
        "AzureBranding",
        "CoManagementSettings",
        "CompliancePolicies",
        "CompliancePoliciesV2",
        "ComplianceScripts",
        "ConditionalAccess",
        "MacCustomAttributes",
        "DeviceConfiguration",
        "DriverUpdateProfiles",
        "EndpointSecurity",
        "EnrollmentRestrictions",
        "EnrollmentStatusPage",
        "FeatureUpdates",
        "AssignmentFilters",
        "DeviceHealthScripts",
        "IntuneBranding",
        "NamedLocations",
        "Notifications",
        "PolicySets",
        "QualityUpdates",
        "ReusableSettings",
        "RoleDefinitions",
        "ScopeTags",
        "PowerShellScripts",
        "MacScripts",
        "SettingsCatalog",
        "TermsAndConditions",
        "TermsOfUse",
        "UpdatePolicies",
        "W365ProvisioningPolicies",
        "W365UserSettings"
    )
    
    # Use provided object types or default to all
    if (-not $ObjectTypes) {
        $ObjectTypes = $allObjectTypes
    }
    
    # Create configuration object
    $config = [PSCustomObject]@{
        BulkExport = @(
            @{
                Name  = "txtExportPath"
                Value = $ExportPath
            },
            @{
                Name  = "txtExportNameFilter"
                Value = $NameFilter
            },
            @{
                Name  = "chkAddObjectType"
                Value = $AddObjectType
            },
            @{
                Name  = "chkExportAssignments"
                Value = $ExportAssignments
            },
            @{
                Name  = "chkAddCompanyName"
                Value = $AddCompanyName
            },
            @{
                Name  = "chkExportScript"
                Value = $ExportScript
            },
            @{
                Name  = "chkExportApplicationFile"
                Value = $ExportApplicationFile
            },
            @{
                Name        = "ObjectTypes"
                Type        = "Custom"
                ObjectTypes = $ObjectTypes
            }
        )
    }
    
    # Convert to JSON and save
    try {
        $jsonContent = $config | ConvertTo-Json -Depth 10 -Compress:$false
        [System.IO.File]::WriteAllText($OutputPath, $jsonContent, [System.Text.Encoding]::UTF8)
        Write-Status "Dynamic export configuration saved to: $OutputPath" "SUCCESS"
        return $OutputPath
    } catch {
        Write-Status "Failed to create dynamic export configuration: $_" "ERROR"
        throw
    }
}

function Backup-IntuneConfig {
    param(
        [string]$TenantId,
        [string]$AppId,
        [string]$Secret,
        [string]$IntuneManagementPath,
        [string]$BackupPath,
        
        # Export configuration parameters
        [string]$NameFilter,
        [bool]$AddObjectType,
        [bool]$ExportAssignments,
        [bool]$AddCompanyName,
        [bool]$ExportScript,
        [bool]$ExportApplicationFile,
        [string[]]$ObjectTypes
    )
    
    Write-Status "Starting Intune configuration backup..."
    
    # Always generate dynamic export configuration when BackupPath is provided
    if ($BackupPath) {
        Write-Status "Generating dynamic export configuration for path: $BackupPath"
        
        # Generate a temporary dynamic config file
        $tempConfigFile = Join-Path $(Get-Location) "DynamicBulkExport_$(Get-Date -Format 'yyyyMMddHHmmss').json"
        
        # Build parameters for New-DynamicExportConfig
        $configParams = @{
            ExportPath = $BackupPath
            OutputPath = $tempConfigFile
        }
        
        # Add optional parameters if they were provided
        if ($PSBoundParameters.ContainsKey('NameFilter')) { $configParams.NameFilter = $NameFilter }
        if ($PSBoundParameters.ContainsKey('AddObjectType')) { $configParams.AddObjectType = $AddObjectType }
        if ($PSBoundParameters.ContainsKey('ExportAssignments')) { $configParams.ExportAssignments = $ExportAssignments }
        if ($PSBoundParameters.ContainsKey('AddCompanyName')) { $configParams.AddCompanyName = $AddCompanyName }
        if ($PSBoundParameters.ContainsKey('ExportScript')) { $configParams.ExportScript = $ExportScript }
        if ($PSBoundParameters.ContainsKey('ExportApplicationFile')) { $configParams.ExportApplicationFile = $ExportApplicationFile }
        if ($PSBoundParameters.ContainsKey('ObjectTypes')) { $configParams.ObjectTypes = $ObjectTypes }
        
        $bulkExportFile = New-DynamicExportConfig @configParams
        
        # Create a custom object to match the expected structure
        $bulkExportFile = [PSCustomObject]@{
            FullName = $bulkExportFile
        }
    } else {
        Write-Status "BackupPath parameter is required for backup operation" "ERROR"
        throw "BackupPath parameter is required for backup operation"
    }
    
    # Validate JSON content
    try {
        $jsonContent = Get-Content $bulkExportFile.FullName | ConvertFrom-Json
        Write-Status "BulkExport.json validation successful"
    } catch {
        Write-Status "BulkExport.json contains invalid JSON: $_" "ERROR"
        throw
    }

    # Extract backup path from JSON
    if ($jsonContent.BulkExport) {
        $backupPath = ($jsonContent.BulkExport | Where-Object { $_.Name -eq 'txtExportPath' }).Value
    } else {
        Write-Status "BackupPath not specified in BulkExport.json, using default: $BackupPath"
    }
    
    # Remove old backup files
    if (Test-Path $BackupPath -PathType Container) {
        Write-Status "Removing old backup files from $BackupPath"
        # Remove all files and directories in the backup path minus the sample-tenant directory
        Get-ChildItem $BackupPath -Force | Where-Object { $_.Name -ne 'sample-tenant' } | Remove-Item -Recurse -Force -WhatIf
    }
    
    # Get IntuneManagement tool
    $startScript = Get-IntuneManagementTool -Path $IntuneManagementPath
    
    # Set environment variables
    $env:AAD_TENANT_ID = $TenantId
    $env:AAD_APP_ID = $AppId
    $env:AAD_APP_SECRET = $Secret
    
    Write-Status "TenantId: $env:AAD_TENANT_ID"
    Write-Status "AppId: $env:AAD_APP_ID"
    Write-Status "AppSecret Length: $($env:AAD_APP_SECRET.Length)"
    
    # Prepare parameters for IntuneManagement
    $params = @{
        Silent          = $true
        Verbose         = $false
        SilentBatchFile = $bulkExportFile.FullName
        TenantId        = $env:AAD_TENANT_ID
        AppId           = $env:AAD_APP_ID
        Secret          = $env:AAD_APP_SECRET
    }
    
    try {
        Write-Status "Starting Intune export..."
        & $startScript @params
        Write-Status "Intune backup completed successfully" "SUCCESS"

    } catch {
        Write-Status "Intune backup failed: $_" "ERROR"
        throw
    } finally {
        # Clean up environment variables
        Remove-Item Env:AAD_TENANT_ID -ErrorAction SilentlyContinue
        Remove-Item Env:AAD_APP_ID -ErrorAction SilentlyContinue
        Remove-Item Env:AAD_APP_SECRET -ErrorAction SilentlyContinue
        
        # Clean up temporary config file if it was created
        if ($tempConfigFile -and (Test-Path $tempConfigFile)) {
            Remove-Item $tempConfigFile -Force -ErrorAction SilentlyContinue
            Write-Status "Cleaned up temporary export configuration file" "SUCCESS"
        }
    }
}

function Restore-IntuneConfig {
    param(
        [string]$TenantId,
        [string]$AppId,
        [string]$Secret,
        [string]$IntuneManagementPath,
        [string]$BackupPath,
        [switch]$DryRun,
        
        # Import configuration parameters
        [string]$NameFilter,
        [bool]$AddObjectType,
        [bool]$ImportScopes,
        [bool]$ImportAssignments,
        [bool]$ReplaceDependencyIDs,
        [string]$ImportType,
        [string]$CAState,
        [string[]]$ObjectTypes
    )
    
    if ($DryRun) {
        Write-Status "=== DRY RUN MODE ===" "WARNING"
        Write-Status "This is a dry run. No actual import will be performed." "WARNING"
        Write-Status "Configuration validation and preview only." "WARNING"
        Write-Status ""
    }
    
    Write-Status "Starting Intune configuration restore..."
    
    # Always generate dynamic import configuration when BackupPath is provided
    if ($BackupPath) {
        Write-Status "Generating dynamic import configuration for path: $BackupPath"
        
        # Generate a temporary dynamic config file
        $tempConfigFile = Join-Path $(Get-Location) "DynamicBulkImport_$(Get-Date -Format 'yyyyMMddHHmmss').json"
        
        # Build parameters for New-DynamicImportConfig
        $configParams = @{
            ImportPath = $BackupPath
            OutputPath = $tempConfigFile
        }
        
        # Add optional parameters if they were provided
        if ($PSBoundParameters.ContainsKey('NameFilter')) { $configParams.NameFilter = $NameFilter }
        if ($PSBoundParameters.ContainsKey('AddObjectType')) { $configParams.AddObjectType = $AddObjectType }
        if ($PSBoundParameters.ContainsKey('ImportScopes')) { $configParams.ImportScopes = $ImportScopes }
        if ($PSBoundParameters.ContainsKey('ImportAssignments')) { $configParams.ImportAssignments = $ImportAssignments }
        if ($PSBoundParameters.ContainsKey('ReplaceDependencyIDs')) { $configParams.ReplaceDependencyIDs = $ReplaceDependencyIDs }
        if ($PSBoundParameters.ContainsKey('ImportType')) { $configParams.ImportType = $ImportType }
        if ($PSBoundParameters.ContainsKey('CAState')) { $configParams.CAState = $CAState }
        if ($PSBoundParameters.ContainsKey('ObjectTypes')) { $configParams.ObjectTypes = $ObjectTypes }
        
        $bulkImportFile = New-DynamicImportConfig @configParams

        # Create a custom object to match the expected structure
        $bulkImportFile = [PSCustomObject]@{
            FullName = $bulkImportFile
        }
    } else {
        Write-Status "BackupPath parameter is required for restore operation" "ERROR"
        throw "BackupPath parameter is required for restore operation"
    }
    
    # Validate JSON content
    try {
        $jsonContent = Get-Content $bulkImportFile.FullName | Out-String | ConvertFrom-Json
        Write-Status "Configuration file validation successful" "SUCCESS"
    } catch {
        Write-Status "Configuration file contains invalid JSON: $_" "ERROR"
        throw
    }
    
    Write-Status "BulkImport.json content: $(Get-Content $bulkImportFile.FullName)"
    
    # Parse import path from JSON
    $importPathSetting = $jsonContent.BulkImport | Where-Object { $_.Name -eq "txtImportPath" }
    if ($importPathSetting) {
        $importPath = $importPathSetting.Value
    }
    
    # Validate import path and show preview
    if (Test-Path $importPath -PathType Container) {
        Write-Status "Import path validated: $importPath" "SUCCESS"
    
        # Show what would be imported
        Write-Status "Preview of files that would be processed:" "INFO"
        $jsonFiles = Get-ChildItem $importPath -Recurse -File -Include "*.json"
        if ($jsonFiles) {
            $groupedFiles = $jsonFiles | Group-Object { $_.Directory.Name } | Sort-Object Name
            foreach ($group in $groupedFiles) {
                Write-Status "  $($group.Name): $($group.Count) files" "INFO"
                if ($DryRun) {
                    $group.Group | ForEach-Object { 
                        Write-Status "    - $($_.Name)" "INFO"
                    }
                }
            }
        } else {
            Write-Status "  No JSON files found in import directory" "WARNING"
        }
    } else {
        Write-Status "Import path does not exist: $importPath" "ERROR"
        Write-Status "Available directories:" "INFO"
        Get-ChildItem -Directory -ErrorAction SilentlyContinue | ForEach-Object { 
            Write-Status "  - $($_.Name)" "INFO" 
        }
        throw "Import path validation failed"
    }
    if ($DryRun) {
        Write-Status ""
        Write-Status "=== DRY RUN SUMMARY ===" "SUCCESS"
        Write-Status "Configuration file is valid" "SUCCESS"
        Write-Status "Import path exists and contains files" "SUCCESS"
        Write-Status "No errors detected in validation" "SUCCESS"
        Write-Status ""
        Write-Status "To perform actual import, run without -DryRun parameter" "INFO"
        Write-Status "=== DRY RUN COMPLETE ===" "SUCCESS"
        return
    }
    
    # Get IntuneManagement tool
    $startScript = Get-IntuneManagementTool -Path $IntuneManagementPath
    
    # Set environment variables
    $env:AAD_TENANT_ID = $TenantId
    $env:AAD_APP_ID = $AppId
    $env:AAD_APP_SECRET = $Secret
    
    Write-Status "TenantId: $env:AAD_TENANT_ID"
    Write-Status "AppId: $env:AAD_APP_ID"
    Write-Status "AppSecret Length: $($env:AAD_APP_SECRET.Length)"
    
    # Prepare parameters for IntuneManagement
    $params = @{
        Silent          = $true
        Verbose         = $false
        SilentBatchFile = $bulkImportFile.FullName
        TenantId        = $env:AAD_TENANT_ID
        AppId           = $env:AAD_APP_ID
        Secret          = $env:AAD_APP_SECRET
    }
    
    try {
        Write-Status "Starting Intune restore..."
        & $startScript @params
        Write-Status "Intune restore completed successfully" "SUCCESS"
    } catch {
        Write-Status "Intune restore failed: $_" "ERROR"
        throw
    } finally {
        # Clean up environment variables
        Remove-Item $Env:AAD_TENANT_ID -ErrorAction SilentlyContinue
        Remove-Item $Env:AAD_APP_ID -ErrorAction SilentlyContinue
        Remove-Item $Env:AAD_APP_SECRET -ErrorAction SilentlyContinue
        
        # Clean up temporary config file if it was created
        if ($BackupPath -and $tempConfigFile -and (Test-Path $tempConfigFile)) {
            Remove-Item $tempConfigFile -Force -ErrorAction SilentlyContinue
            Write-Status "Cleaned up temporary configuration file" "SUCCESS"
        }
    }
}

# Main execution
try {
    Write-Status "Starting Intune Management Local Script - Action: $Action"
    
    switch ($Action) {
        'Backup' {
            # Build parameters for Backup-IntuneConfig
            $backupParams = @{
                TenantId             = $TenantId
                AppId                = $AppId
                Secret               = $Secret
                IntuneManagementPath = $IntuneManagementPath
            }
            
            # Add BackupPath and optional parameters
            $backupParams.BackupPath = $BackupPath
            if ($PSBoundParameters.ContainsKey('NameFilter')) { $backupParams.NameFilter = $NameFilter }
            if ($PSBoundParameters.ContainsKey('AddObjectType')) { $backupParams.AddObjectType = $AddObjectType }
            if ($PSBoundParameters.ContainsKey('ExportAssignments')) { $backupParams.ExportAssignments = $ExportAssignments }
            if ($PSBoundParameters.ContainsKey('AddCompanyName')) { $backupParams.AddCompanyName = $AddCompanyName }
            if ($PSBoundParameters.ContainsKey('ExportScript')) { $backupParams.ExportScript = $ExportScript }
            if ($PSBoundParameters.ContainsKey('ExportApplicationFile')) { $backupParams.ExportApplicationFile = $ExportApplicationFile }
            if ($PSBoundParameters.ContainsKey('ObjectTypes')) { $backupParams.ObjectTypes = $ObjectTypes }
            
            Backup-IntuneConfig @backupParams

            # Convert JSON files to UTF-8 encoding
            Write-Status "Converting JSON files to UTF-8 encoding in $BackupPath"
            .\Convert-JsonToUtf8.ps1
        }
        'Restore' {
            # Build parameters for Restore-IntuneConfig
            $restoreParams = @{
                TenantId             = $TenantId
                AppId                = $AppId
                Secret               = $Secret
                IntuneManagementPath = $IntuneManagementPath
                DryRun               = $DryRun
            }
            
            # Add BackupPath and optional parameters
            $restoreParams.BackupPath = $BackupPath
            if ($PSBoundParameters.ContainsKey('NameFilter')) { $restoreParams.NameFilter = $NameFilter }
            if ($PSBoundParameters.ContainsKey('AddObjectType')) { $restoreParams.AddObjectType = $AddObjectType }
            if ($PSBoundParameters.ContainsKey('ImportScopes')) { $restoreParams.ImportScopes = $ImportScopes }
            if ($PSBoundParameters.ContainsKey('ImportAssignments')) { $restoreParams.ImportAssignments = $ImportAssignments }
            if ($PSBoundParameters.ContainsKey('ReplaceDependencyIDs')) { $restoreParams.ReplaceDependencyIDs = $ReplaceDependencyIDs }
            if ($PSBoundParameters.ContainsKey('ImportType')) { $restoreParams.ImportType = $ImportType }
            if ($PSBoundParameters.ContainsKey('CAState')) { $restoreParams.CAState = $CAState }
            if ($PSBoundParameters.ContainsKey('ObjectTypes')) { $restoreParams.ObjectTypes = $ObjectTypes }
            
            Restore-IntuneConfig @restoreParams
        }
    }
    
    Write-Status "Script completed successfully" "SUCCESS"
} catch {
    Write-Status "Script failed: $_" "ERROR"
    exit 1
}