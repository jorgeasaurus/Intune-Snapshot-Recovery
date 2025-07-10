#Requires -Version 5.1
<#
.SYNOPSIS
    Interactive script to generate BulkExport.json or BulkImport.json configuration files in UTF-8 encoding.

.DESCRIPTION
    This script provides an interactive menu system to configure and generate JSON files for the
    IntuneManagement tool's bulk export and import operations. All files are saved with UTF-8 encoding.

.PARAMETER ConfigType
    Specifies the type of configuration to generate: 'Export' or 'Import'

.PARAMETER OutputPath
    Path where the generated JSON file will be saved

.EXAMPLE
    .\Generate-BulkConfig.ps1
    
.EXAMPLE
    .\Generate-BulkConfig.ps1 -ConfigType Export -OutputPath ".\MyBulkExport.json"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Export', 'Import')]
    [string]$ConfigType,
    
    [Parameter(Mandatory = $false)]
    [string]$OutputPath
)

# Define available object types for Intune Management
$Script:AvailableObjectTypes = @(
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

function Write-Header {
    param([string]$Title)
    Clear-Host
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Yellow
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host ""
}

function Write-Menu {
    param([string[]]$Options, [string]$Title)
    Write-Host $Title -ForegroundColor Green
    Write-Host ("-" * $Title.Length) -ForegroundColor Green
    for ($i = 0; $i -lt $Options.Length; $i++) {
        Write-Host "$($i + 1). $($Options[$i])"
    }
    Write-Host ""
}

function Get-UserChoice {
    param([int]$MaxChoice, [string]$Prompt = "Enter your choice")
    do {
        $choice = Read-Host "$Prompt (1-$MaxChoice)"
        if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $MaxChoice) {
            return [int]$choice
        }
        Write-Host "Invalid choice. Please enter a number between 1 and $MaxChoice." -ForegroundColor Red
    } while ($true)
}

function Get-YesNo {
    param([string]$Prompt)
    do {
        $response = Read-Host "$Prompt (y/n)"
        if ($response -match '^[yY]') { return $true }
        if ($response -match '^[nN]') { return $false }
        Write-Host "Please enter 'y' for yes or 'n' for no." -ForegroundColor Red
    } while ($true)
}

function Select-ObjectTypes {
    param([string[]]$DefaultTypes = @())
    
    Write-Header "Select Object Types to Include"
    Write-Host "Available Object Types:" -ForegroundColor Yellow
    Write-Host ""
    
    $selectedTypes = @()
    
    # Show options
    Write-Host "1. Select All Object Types" -ForegroundColor Green
    Write-Host "2. Select Individual Object Types" -ForegroundColor Green
    Write-Host "3. Use Default Selection" -ForegroundColor Green
    Write-Host ""
    
    $choice = Get-UserChoice -MaxChoice 3 -Prompt "Choose selection method"
    
    switch ($choice) {
        1 {
            $selectedTypes = $Script:AvailableObjectTypes
            Write-Host "All object types selected." -ForegroundColor Green
        }
        2 {
            Write-Host ""
            Write-Host "Select object types (enter numbers separated by commas, or 'all' for all types):" -ForegroundColor Yellow
            
            for ($i = 0; $i -lt $Script:AvailableObjectTypes.Length; $i++) {
                Write-Host "$($i + 1). $($Script:AvailableObjectTypes[$i])"
            }
            
            do {
                $input = Read-Host "Enter your selections"
                if ($input -eq 'all') {
                    $selectedTypes = $Script:AvailableObjectTypes
                    break
                }
                
                $selections = $input -split ',' | ForEach-Object { $_.Trim() }
                $validSelections = @()
                $isValid = $true
                
                foreach ($selection in $selections) {
                    if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $Script:AvailableObjectTypes.Length) {
                        $validSelections += [int]$selection
                    } else {
                        Write-Host "Invalid selection: $selection" -ForegroundColor Red
                        $isValid = $false
                        break
                    }
                }
                
                if ($isValid) {
                    $selectedTypes = $validSelections | ForEach-Object { $Script:AvailableObjectTypes[$_ - 1] }
                    break
                }
            } while ($true)
        }
        3 {
            if ($DefaultTypes.Count -gt 0) {
                $selectedTypes = $DefaultTypes
                Write-Host "Using default object types selection." -ForegroundColor Green
            } else {
                $selectedTypes = $Script:AvailableObjectTypes
                Write-Host "No default types provided. Using all object types." -ForegroundColor Green
            }
        }
    }
    
    Write-Host ""
    Write-Host "Selected Object Types:" -ForegroundColor Yellow
    $selectedTypes | ForEach-Object { Write-Host "  - $_" }
    Write-Host ""
    
    return $selectedTypes
}

function New-ExportConfig {
    Write-Header "Generate Bulk Export Configuration"
    
    # Get export path
    $defaultPath = ".\intune-backup"
    $exportPath = Read-Host "Enter export path (default: $defaultPath)"
    if ([string]::IsNullOrWhiteSpace($exportPath)) {
        $exportPath = $defaultPath
    }
    
    # Get name filter
    $nameFilter = Read-Host "Enter name filter (leave empty for no filter)"
    
    # Get boolean options
    $addObjectType = Get-YesNo "Add object type to exported files?"
    $exportAssignments = Get-YesNo "Export assignments?"
    $addCompanyName = Get-YesNo "Add company name to exported files?"
    $exportScript = Get-YesNo "Export PowerShell scripts?"
    $exportApplicationFile = Get-YesNo "Export application files?"
    
    # Select object types
    $selectedTypes = Select-ObjectTypes -DefaultTypes $Script:AvailableObjectTypes
    
    # Create configuration object
    $config = [PSCustomObject]@{
        BulkExport = @(
            @{
                Name = "txtExportPath"
                Value = $exportPath
            },
            @{
                Name = "txtExportNameFilter"
                Value = $nameFilter
            },
            @{
                Name = "chkAddObjectType"
                Value = $addObjectType
            },
            @{
                Name = "chkExportAssignments"
                Value = $exportAssignments
            },
            @{
                Name = "chkAddCompanyName"
                Value = $addCompanyName
            },
            @{
                Name = "chkExportScript"
                Value = $exportScript
            },
            @{
                Name = "chkExportApplicationFile"
                Value = $exportApplicationFile
            },
            @{
                Name = "ObjectTypes"
                Type = "Custom"
                ObjectTypes = $selectedTypes
            }
        )
    }
    
    return $config
}

function New-ImportConfig {
    Write-Header "Generate Bulk Import Configuration"
    
    # Get import path
    $defaultPath = ".\intune-backup"
    $importPath = Read-Host "Enter import path (default: $defaultPath)"
    if ([string]::IsNullOrWhiteSpace($importPath)) {
        $importPath = $defaultPath
    }
    
    # Get name filter
    $nameFilter = Read-Host "Enter name filter (default: ' - Restore')"
    if ([string]::IsNullOrWhiteSpace($nameFilter)) {
        $nameFilter = " - Restore"
    }
    
    # Get boolean options
    $addObjectType = Get-YesNo "Add object type to imported files?"
    $importScopes = Get-YesNo "Import scopes?"
    $importAssignments = Get-YesNo "Import assignments?"
    $replaceDependencyIDs = Get-YesNo "Replace dependency IDs?"
    
    # Get import type
    Write-Host ""
    Write-Host "Import Type Options:" -ForegroundColor Yellow
    $importTypes = @("skipIfExist", "overwrite", "append")
    Write-Menu -Options $importTypes -Title "Select Import Type"
    $importTypeChoice = Get-UserChoice -MaxChoice $importTypes.Length
    $importType = $importTypes[$importTypeChoice - 1]
    
    # Get Conditional Access state
    Write-Host ""
    Write-Host "Conditional Access State Options:" -ForegroundColor Yellow
    $caStates = @("disabled", "enabled", "enabledForReportingButNotEnforced")
    Write-Menu -Options $caStates -Title "Select Conditional Access State"
    $caStateChoice = Get-UserChoice -MaxChoice $caStates.Length
    $caState = $caStates[$caStateChoice - 1]
    
    # Select object types
    $selectedTypes = Select-ObjectTypes -DefaultTypes $Script:AvailableObjectTypes
    
    # Create configuration object
    $config = [PSCustomObject]@{
        BulkImport = @(
            @{
                Name = "txtImportPath"
                Value = $importPath
            },
            @{
                Name = "txtImportNameFilter"
                Value = $nameFilter
            },
            @{
                Name = "chkAddObjectType"
                Value = $addObjectType
            },
            @{
                Name = "chkImportScopes"
                Value = $importScopes
            },
            @{
                Name = "chkImportAssignments"
                Value = $importAssignments
            },
            @{
                Name = "chkReplaceDependencyIDs"
                Value = $replaceDependencyIDs
            },
            @{
                Name = "cbImportType"
                Value = $importType
            },
            @{
                Name = "cbImportCAState"
                Value = $caState
            },
            @{
                Name = "ObjectTypes"
                Type = "Custom"
                ObjectTypes = $selectedTypes
            }
        )
    }
    
    return $config
}

function Save-ConfigFile {
    param([PSCustomObject]$Config, [string]$FilePath)
    
    try {
        # Convert to JSON with proper formatting
        $jsonContent = $Config | ConvertTo-Json -Depth 10 -Compress:$false
        
        # Save with UTF-8 encoding
        [System.IO.File]::WriteAllText($FilePath, $jsonContent, [System.Text.Encoding]::UTF8)
        
        Write-Host "Configuration saved successfully to: $FilePath" -ForegroundColor Green
        Write-Host "File encoding: UTF-8" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "Error saving configuration: $_" -ForegroundColor Red
        return $false
    }
}

function Show-MainMenu {
    Write-Header "Intune Management Bulk Configuration Generator"
    
    $options = @(
        "Generate Bulk Export Configuration",
        "Generate Bulk Import Configuration",
        "Exit"
    )
    
    Write-Menu -Options $options -Title "Main Menu"
    
    return Get-UserChoice -MaxChoice $options.Length
}

# Main execution
try {
    if ($ConfigType -and $OutputPath) {
        # Non-interactive mode
        switch ($ConfigType) {
            'Export' {
                $config = New-ExportConfig
                $success = Save-ConfigFile -Config $config -FilePath $OutputPath
            }
            'Import' {
                $config = New-ImportConfig
                $success = Save-ConfigFile -Config $config -FilePath $OutputPath
            }
        }
        
        if ($success) {
            Write-Host "Configuration generated successfully!" -ForegroundColor Green
        }
    }
    else {
        # Interactive mode
        do {
            $choice = Show-MainMenu
            
            switch ($choice) {
                1 {
                    $config = New-ExportConfig
                    $defaultFileName = "BulkExport.json"
                    $filePath = Read-Host "Enter output file path (default: $defaultFileName)"
                    if ([string]::IsNullOrWhiteSpace($filePath)) {
                        $filePath = $defaultFileName
                    }
                    Save-ConfigFile -Config $config -FilePath $filePath
                    Read-Host "Press Enter to continue"
                }
                2 {
                    $config = New-ImportConfig
                    $defaultFileName = "BulkImport.json"
                    $filePath = Read-Host "Enter output file path (default: $defaultFileName)"
                    if ([string]::IsNullOrWhiteSpace($filePath)) {
                        $filePath = $defaultFileName
                    }
                    Save-ConfigFile -Config $config -FilePath $filePath
                    Read-Host "Press Enter to continue"
                }
                3 {
                    Write-Host "Exiting..." -ForegroundColor Yellow
                    break
                }
            }
        } while ($choice -ne 3)
    }
}
catch {
    Write-Host "An error occurred: $_" -ForegroundColor Red
    exit 1
}