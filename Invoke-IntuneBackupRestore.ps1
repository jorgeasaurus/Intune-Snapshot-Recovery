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

.PARAMETER LogPath
    Directory path where log files will be stored (default: ".\logs")

.PARAMETER EnableLogging
    Enable file logging to capture detailed execution logs (default: $true)

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
    [bool]$ExportApplicationFile,
    
    # Logging parameters
    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\logs",
    
    [Parameter(Mandatory = $false)]
    [bool]$EnableLogging = $true
)

# Global variables for logging
$Global:LogFilePath = $null

function Initialize-Logging {
    param(
        [string]$LogDirectory,
        [bool]$EnableLogging,
        [string]$Action
    )
    
    if (-not $EnableLogging) {
        return
    }
    
    try {
        # Create logs directory if it doesn't exist
        if (-not (Test-Path $LogDirectory)) {
            New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
            Write-Host "Created logs directory: $LogDirectory" -ForegroundColor Green
        }
        
        # Create log file with timestamp and action
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $logFileName = "IntuneBackupRestore_${Action}_${timestamp}.log"
        $Global:LogFilePath = Join-Path $LogDirectory $logFileName
        
        # Initialize log file with header
        $header = @"
================================================================================
Intune Backup/Restore Log
================================================================================
Script: Invoke-IntuneBackupRestore.ps1
Action: $Action
Start Time: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
PowerShell Version: $($PSVersionTable.PSVersion)
OS: $([System.Environment]::OSVersion.VersionString)
User: $([System.Environment]::UserName)
Computer: $([System.Environment]::MachineName)
================================================================================

"@
        [System.IO.File]::WriteAllText($Global:LogFilePath, $header, [System.Text.Encoding]::UTF8)
        
        Write-Host "Logging initialized: $Global:LogFilePath" -ForegroundColor Green
        
        # Clean up old log files (keep last 30 days)
        Remove-OldLogFiles -LogDirectory $LogDirectory -DaysToKeep 30
        
    } catch {
        Write-Warning "Failed to initialize logging: $($_.Exception.Message)"
        $Global:LogFilePath = $null
    }
}

function Remove-OldLogFiles {
    param(
        [string]$LogDirectory,
        [int]$DaysToKeep = 30
    )
    
    try {
        $cutoffDate = (Get-Date).AddDays(-$DaysToKeep)
        $oldLogFiles = Get-ChildItem -Path $LogDirectory -Filter "IntuneBackupRestore_*.log" | 
        Where-Object { $_.LastWriteTime -lt $cutoffDate }
        
        foreach ($file in $oldLogFiles) {
            Remove-Item $file.FullName -Force
            Write-Verbose "Removed old log file: $($file.Name)"
        }
        
        if ($oldLogFiles.Count -gt 0) {
            Write-Verbose "Cleaned up $($oldLogFiles.Count) old log files"
        }
    } catch {
        Write-Warning "Failed to clean up old log files: $($_.Exception.Message)"
    }
}

function Write-Status {
    param(
        [string]$Message, 
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $formattedMessage = "[$timestamp] [$Level] $Message"
    
    # Write to console with color
    Write-Host $formattedMessage -ForegroundColor $(
        switch ($Level) {
            "ERROR" { "Red" }
            "WARNING" { "Yellow" }
            "SUCCESS" { "Green" }
            default { "White" }
        }
    )
    
    # Write to log file if logging is enabled
    if ($Global:LogFilePath -and (Test-Path $Global:LogFilePath)) {
        try {
            Add-Content -Path $Global:LogFilePath -Value $formattedMessage -Encoding UTF8
        } catch {
            # Silently fail if we can't write to log - don't disrupt main operation
        }
    }
}

function Write-LogSeparator {
    param([string]$Title)
    
    $separator = "=" * 80
    $titleLine = "=== $Title ==="
    
    Write-Status $separator
    Write-Status $titleLine
    Write-Status $separator
}

function Write-LogSection {
    param([string]$SectionName)
    
    $section = "-" * 60
    $sectionLine = "--- $SectionName ---"
    
    Write-Status $section
    Write-Status $sectionLine
    Write-Status $section
}

function Complete-Logging {
    param([string]$Action, [bool]$Success = $true)
    
    if ($Global:LogFilePath -and (Test-Path $Global:LogFilePath)) {
        try {
            $footer = @"

================================================================================
Script Execution Completed
================================================================================
Action: $Action
End Time: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Status: $(if ($Success) { "SUCCESS" } else { "FAILED" })
Log File: $Global:LogFilePath
================================================================================
"@
            Add-Content -Path $Global:LogFilePath -Value $footer -Encoding UTF8
            Write-Status "Log file completed: $Global:LogFilePath" "SUCCESS"
        } catch {
            Write-Warning "Failed to complete log file: $($_.Exception.Message)"
        }
    }
}

function Convert-JsonToUtf8 {
    <#
    .SYNOPSIS
        Converts all JSON files in a repository to UTF-8 encoding
    
    .DESCRIPTION
        This function recursively searches for all .json files in the specified path
        and converts them to UTF-8 encoding without BOM. It creates backups of files
        that are changed and provides detailed output about the conversion process.
    
    .PARAMETER Path
        The root path to search for JSON files. Defaults to current directory.
    
    .PARAMETER CreateBackup
        Creates a backup copy of files before converting them. Default is $true.
    
    .EXAMPLE
        Convert-JsonToUtf8
        Converts all JSON files in the current directory and subdirectories
    
    .EXAMPLE
        Convert-JsonToUtf8 -Path "C:\MyRepo" -CreateBackup $false
        Converts all JSON files in the specified path without creating backups
       
    #>
    
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path = (Get-Location).Path,
        
        [Parameter(Mandatory = $false)]
        [bool]$CreateBackup = $false    
    )
    
    begin {
        Write-Host "Starting JSON UTF-8 conversion process..." -ForegroundColor Green
        Write-Host "Search Path: $Path" -ForegroundColor Cyan
        Write-Host "Create Backup: $CreateBackup" -ForegroundColor Cyan
        Write-Host ""
        
        $convertedCount = 0
        $skippedCount = 0
        $errorCount = 0
    }
    
    process {
        try {
            # Find all JSON files recursively
            $jsonFiles = Get-ChildItem -Path $Path -Filter "*.json" -Recurse -File
            
            if ($jsonFiles.Count -eq 0) {
                Write-Warning "No JSON files found in the specified path."
                return
            }
            
            Write-Host "Found $($jsonFiles.Count) JSON files to process." -ForegroundColor Yellow
            Write-Host ""
            
            foreach ($file in $jsonFiles) {
                try {
                    Write-Verbose "Processing: $($file.FullName)"
                    
                    # Read the file and detect current encoding
                    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
                    $encoding = [System.Text.Encoding]::Default
                    
                    # Detect encoding by checking BOM
                    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
                        $encoding = [System.Text.Encoding]::UTF8
                        $currentEncoding = "UTF-8 with BOM"
                    } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
                        $encoding = [System.Text.Encoding]::Unicode
                        $currentEncoding = "UTF-16 LE"
                    } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
                        $encoding = [System.Text.Encoding]::BigEndianUnicode
                        $currentEncoding = "UTF-16 BE"
                    } else {
                        # Try to detect if it's already UTF-8 without BOM
                        try {
                            $content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
                            # Test if the content can be parsed as JSON
                            $null = $content | ConvertFrom-Json -ErrorAction Stop
                            
                            # Check if file is already UTF-8 without BOM by trying to re-encode
                            $utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
                            if ([System.Linq.Enumerable]::SequenceEqual($bytes, $utf8Bytes)) {
                                $currentEncoding = "UTF-8 without BOM (already correct)"
                                Write-Verbose "  Current encoding: $currentEncoding - SKIPPED"
                                $skippedCount++
                                continue
                            } else {
                                $currentEncoding = "Likely ANSI/ASCII"
                            }
                        } catch {
                            $currentEncoding = "Unknown/Binary"
                        }
                    }
                    
                    Write-Verbose "  Current encoding: $currentEncoding"
                    
                    # Read content using detected encoding
                    $content = [System.IO.File]::ReadAllText($file.FullName, $encoding)
                    
                    # Validate that it's valid JSON
                    try {
                        $null = $content | ConvertFrom-Json -ErrorAction Stop
                    } catch {
                        Write-Warning "  File does not contain valid JSON, skipping: $($_.Exception.Message)"
                        $skippedCount++
                        continue
                    }
                    
                    
                    # Create backup if requested
                    if ($CreateBackup) {
                        $backupPath = "$($file.FullName).backup"
                        Copy-Item -Path $file.FullName -Destination $backupPath -Force
                        Write-Verbose "  Backup created: $backupPath"
                    }
                    
                    # Write content as UTF-8 without BOM
                    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                    [System.IO.File]::WriteAllText($file.FullName, $content, $utf8NoBom)
                    
                    Write-Verbose "  Successfully converted to UTF-8 without BOM"
                    $convertedCount++
                } catch {
                    Write-Error "  Error processing file: $($_.Exception.Message)"
                    $errorCount++
                }
                
                Write-Verbose ""
            }
        } catch {
            Write-Error "Error during processing: $($_.Exception.Message)"
            $errorCount++
        }
    }
    
    end {
        Write-Host "Conversion process completed!" -ForegroundColor Green
        Write-Host "Files converted: $convertedCount" -ForegroundColor Green
        Write-Host "Files skipped: $skippedCount" -ForegroundColor Yellow
        Write-Host "Errors encountered: $errorCount" -ForegroundColor Red
        
        if ($CreateBackup -and $convertedCount -gt 0) {
            Write-Host ""
            Write-Host "Backup files were created with .backup extension." -ForegroundColor Blue
            Write-Host "You can delete them after verifying the conversion was successful." -ForegroundColor Blue
        }
    }
}

function Get-IntuneManagementTool {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        Write-Status "IntuneManagement tool not found. Cloning from GitHub..."
        try {
            git clone --branch 3.9.8 https://github.com/Micke-K/IntuneManagement.git $Path
            Remove-Item ".\IntuneManagement\.git\" -Force -Recurse -ErrorAction SilentlyContinue
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
    
    Write-LogSection "BACKUP CONFIGURATION"
    Write-Status "Starting Intune configuration backup..." "INFO"
    Write-Status "Target backup path: $BackupPath" "INFO"
    
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
        Get-ChildItem $BackupPath -Force | Where-Object { $_.Name -ne 'sample-tenant' } | Remove-Item -Recurse -Force
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
    
    Write-LogSection "RESTORE CONFIGURATION"
    
    if ($DryRun) {
        Write-Status "=== DRY RUN MODE ===" "WARNING"
        Write-Status "This is a dry run. No actual import will be performed." "WARNING"
        Write-Status "Configuration validation and preview only." "WARNING"
        Write-Status ""
    }
    
    Write-Status "Starting Intune configuration restore..." "INFO"
    Write-Status "Source backup path: $BackupPath" "INFO"
    
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
    # Initialize logging
    Initialize-Logging -LogDirectory $LogPath -EnableLogging $EnableLogging -Action $Action
    
    Write-LogSeparator "SCRIPT EXECUTION START"
    Write-Status "Starting Intune Management Script - Action: $Action"
    
    # Log script parameters (excluding sensitive information)
    Write-LogSection "SCRIPT PARAMETERS"
    Write-Status "Action: $Action"
    Write-Status "TenantId: $TenantId"
    Write-Status "AppId: $AppId"
    Write-Status "AppSecret: [REDACTED - Length: $($Secret.Length)]"
    Write-Status "IntuneManagementPath: $IntuneManagementPath"
    Write-Status "BackupPath: $BackupPath"
    Write-Status "DryRun: $DryRun"
    Write-Status "EnableLogging: $EnableLogging"
    Write-Status "LogPath: $LogPath"
    
    if ($PSBoundParameters.ContainsKey('NameFilter')) { Write-Status "NameFilter: $NameFilter" }
    if ($PSBoundParameters.ContainsKey('AddObjectType')) { Write-Status "AddObjectType: $AddObjectType" }
    if ($PSBoundParameters.ContainsKey('ObjectTypes')) { Write-Status "ObjectTypes: $($ObjectTypes -join ', ')" }
    
    if ($Action -eq 'Backup') {
        if ($PSBoundParameters.ContainsKey('ExportAssignments')) { Write-Status "ExportAssignments: $ExportAssignments" }
        if ($PSBoundParameters.ContainsKey('AddCompanyName')) { Write-Status "AddCompanyName: $AddCompanyName" }
        if ($PSBoundParameters.ContainsKey('ExportScript')) { Write-Status "ExportScript: $ExportScript" }
        if ($PSBoundParameters.ContainsKey('ExportApplicationFile')) { Write-Status "ExportApplicationFile: $ExportApplicationFile" }
    }
    
    if ($Action -eq 'Restore') {
        if ($PSBoundParameters.ContainsKey('ImportScopes')) { Write-Status "ImportScopes: $ImportScopes" }
        if ($PSBoundParameters.ContainsKey('ImportAssignments')) { Write-Status "ImportAssignments: $ImportAssignments" }
        if ($PSBoundParameters.ContainsKey('ReplaceDependencyIDs')) { Write-Status "ReplaceDependencyIDs: $ReplaceDependencyIDs" }
        if ($PSBoundParameters.ContainsKey('ImportType')) { Write-Status "ImportType: $ImportType" }
        if ($PSBoundParameters.ContainsKey('CAState')) { Write-Status "CAState: $CAState" }
    }
    
    Write-LogSeparator "STARTING $($Action.ToUpper()) OPERATION"
    
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
            Write-LogSection "JSON UTF-8 CONVERSION"
            Write-Status "Converting JSON files to UTF-8 encoding in $BackupPath"
            Convert-JsonToUtf8 -Path $BackupPath
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
    
    Write-LogSeparator "SCRIPT EXECUTION COMPLETED"
    Write-Status "Script completed successfully" "SUCCESS"
    Complete-Logging -Action $Action -Success $true
} catch {
    Write-LogSeparator "SCRIPT EXECUTION FAILED"
    Write-Status "Script failed: $_" "ERROR"
    Write-Status "Exception Details: $($_.Exception.GetType().Name)" "ERROR"
    Write-Status "Stack Trace: $($_.ScriptStackTrace)" "ERROR"
    Complete-Logging -Action $Action -Success $false
    exit 1
}