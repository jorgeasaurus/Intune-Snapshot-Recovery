#Requires -Version 5.1
<#
.SYNOPSIS
    Local PowerShell script that duplicates the functionality of the GitHub workflows for Intune Management backup and restore.

.DESCRIPTION
    This script provides two main functions:
    1. Backup-IntuneConfig - Exports Intune configuration using the IntuneManagement tool
    2. Restore-IntuneConfig - Imports Intune configuration using the IntuneManagement tool
    
    The script requires Azure AD app registration credentials and will clone the IntuneManagement
    repository if it doesn't exist locally.

.PARAMETER Action
    Specifies the action to perform: 'Backup' or 'Restore'

.PARAMETER TenantId
    Azure AD Tenant ID

.PARAMETER AppId
    Azure AD Application (Client) ID

.PARAMETER Secret
    Azure AD Application Client Secret

.PARAMETER IntuneManagementPath
    Path to the IntuneManagement tool (will be cloned if not present)

.PARAMETER BackupPath
    Path where backup files will be stored/read from

.EXAMPLE
    .\IntuneManagement-Local.ps1 -Action Backup -TenantId "your-tenant-id" -AppId "your-app-id" -Secret "your-secret"

.EXAMPLE
    .\IntuneManagement-Local.ps1 -Action Restore -TenantId "your-tenant-id" -AppId "your-app-id" -Secret "your-secret"
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
    
    [Parameter(Mandatory = $false)]
    [string]$BackupPath = ".\intune-backup",

    [Parameter(Mandatory = $false)]
    [string]$SilentBatchFile = "BulkExport.json",
    
    [Parameter(Mandatory = $false)]
    [switch]$DryRun
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
    
    Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue

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

function Backup-IntuneConfig {
    param(
        [string]$TenantId,
        [string]$AppId,
        [string]$Secret,
        [string]$IntuneManagementPath,
        [string]$BackupPath
    )
    
    Write-Status "Starting Intune configuration backup..."
    
    # Validate BulkExport.json exists
    $bulkExportFile = Get-ChildItem -Filter $SilentBatchFile -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $bulkExportFile) {
        Write-Status "BulkExport.json not found in current directory or subdirectories" "ERROR"
        throw "BulkExport.json is required for backup operation"
    }
    
    # Validate JSON content
    try {
        $jsonContent = Get-Content $bulkExportFile.FullName | Out-String | ConvertFrom-Json
        Write-Status "BulkExport.json validation successful"
    } catch {
        Write-Status "BulkExport.json contains invalid JSON: $_" "ERROR"
        throw
    }

    # Extract backup path from JSON
    if ($jsonContent.BackupPath) {
        $BackupPath = $jsonContent.BackupPath
    } else {
        Write-Status "BackupPath not specified in BulkExport.json, using default: $BackupPath"
    }
    
    # Remove old backup files
    if (Test-Path $BackupPath -PathType Container) {
        Write-Status "Removing old backup files from $BackupPath"
        Remove-Item $BackupPath -Recurse -Force
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
    }
}

function Restore-IntuneConfig {
    param(
        [string]$TenantId,
        [string]$AppId,
        [string]$Secret,
        [string]$IntuneManagementPath,
        [switch]$DryRun
    )
    
    if ($DryRun) {
        Write-Status "=== DRY RUN MODE ===" "WARNING"
        Write-Status "This is a dry run. No actual import will be performed." "WARNING"
        Write-Status "Configuration validation and preview only." "WARNING"
        Write-Status ""
    }
    
    Write-Status "Starting Intune configuration restore..."
    
    # Validate BulkImport.json exists
    $bulkImportFile = Get-ChildItem -Filter "BulkImport.json" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $bulkImportFile) {
        Write-Status "BulkImport.json not found in current directory or subdirectories" "ERROR"
        throw "BulkImport.json is required for restore operation"
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
    $importPath = ".\intune-backup"  # default
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
        Verbose         = $true
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
    }
}

# Main execution
try {
    Write-Status "Starting Intune Management Local Script - Action: $Action"
    
    switch ($Action) {
        'Backup' {
            Backup-IntuneConfig -TenantId $TenantId -AppId $AppId -Secret $Secret -IntuneManagementPath $IntuneManagementPath -BackupPath $BackupPath
        }
        'Restore' {
            Restore-IntuneConfig -TenantId $TenantId -AppId $AppId -Secret $Secret -IntuneManagementPath $IntuneManagementPath -DryRun:$DryRun
        }
    }
    
    Write-Status "Script completed successfully" "SUCCESS"
} catch {
    Write-Status "Script failed: $_" "ERROR"
    exit 1
}