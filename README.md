# Intune Snapshot Recovery

A comprehensive toolkit for backing up, restoring, and managing Microsoft Intune tenant configurations using automated workflows and PowerShell scripts.

## 🚀 Overview

This repository provides automated solutions for:
- **Tenant Snapshots**: Create point-in-time backups of your entire Intune tenant
- **Configuration Recovery**: Restore specific policies or entire tenant configurations
- **Environment Migration**: Copy configurations between tenants (DEV → PROD)
- **Disaster Recovery**: Quickly restore tenant state from snapshots
- **Policy Management**: Bulk import/export of Intune policies and configurations

## 📁 Repository Structure

```
├── .github/workflows/              # GitHub Actions workflows
│   ├── IntuneExportParameterized.yml    # Parameterized export workflow
│   ├── IntuneImportParameterized.yml    # Parameterized import workflow
│   └──  IntuneManagementBackup.yml       # Scheduled backup workflow
├── intune-backup/                  # Backup storage directory
│   └── [tenant-name]/             # Tenant-specific backups
│       ├── Applications/
│       ├── CompliancePolicies/
│       ├── DeviceConfiguration/
│       └── [other-policy-types]/
├── IntuneManagement-Local.ps1      # Local backup/restore script
└── README.md
```

## 🛠️ Prerequisites

### Azure AD App Registration
You'll need an Azure AD app registration with the following permissions:

**Microsoft Graph API Permissions:**
- `DeviceManagementApps.ReadWrite.All`
- `DeviceManagementConfiguration.ReadWrite.All`
- `DeviceManagementManagedDevices.ReadWrite.All`
- `DeviceManagementServiceConfig.ReadWrite.All`
- `Group.Read.All`
- `GroupMember.Read.All`
- `User.Read.All`

**Directory (Azure AD) Graph Permissions:**
- `Policy.ReadWrite.ConditionalAccess`
- `Policy.Read.All`

### Required Secrets (for GitHub Actions)
Configure these secrets in your GitHub repository:
- `AZURE_TENANT_ID`: Your Azure AD tenant ID
- `AZURE_CLIENT_ID`: Azure AD app registration client ID
- `AZURE_CLIENT_SECRET`: Azure AD app registration client secret

### Local Requirements
- PowerShell 5.1 or later
- Git (for cloning IntuneManagement tool)
- Internet connection (to download dependencies)

## 🚀 Quick Start

### 1. Clone Repository
```bash
git clone <your-repo-url>
cd intune-snapshot-recovery
```

### 2. Local Backup (PowerShell)
```powershell
# Basic backup
.\IntuneManagement-Local.ps1 -Action Backup -TenantId "your-tenant-id" -AppId "your-app-id" -Secret "your-secret"

# Customized backup
.\IntuneManagement-Local.ps1 -Action Backup -TenantId "your-tenant-id" -AppId "your-app-id" -Secret "your-secret" -SilentBatchFile = "BulkExportCustom.json"
```

### 3. Local Restore (PowerShell)
```powershell
# Restore from backup
.\IntuneManagement-Local.ps1 -Action Restore -TenantId "your-tenant-id" -AppId "your-app-id" -Secret "your-secret"
```

### 4. GitHub Actions Workflows

#### Automated Daily Backup
The `IntuneManagementBackup.yml` workflow runs daily at 14:00 UTC and can be triggered manually.

#### Parameterized Export
Use `IntuneExportParameterized.yml` for custom export operations:
1. Go to **Actions** → **Intune Export - Parameterized**
2. Click **Run workflow**
3. Configure parameters:
   - Export path
   - Object types to include
   - Export options (assignments, scripts, etc.)

#### Parameterized Import
Use `IntuneImportParameterized.yml` for custom import operations:
1. Go to **Actions** → **Intune Import - Parameterized**
2. Click **Run workflow**
3. Configure parameters:
   - Import path
   - Import behavior (skip/overwrite/append)
   - Conditional Access state
   - **Dry run option** for testing

## 📝 Configuration Files

### BulkExport.json
Controls what gets exported:
```json
{
    "BulkExport": [
        {
            "Name": "txtExportPath",
            "Value": ".\\intune-backup"
        },
        {
            "Name": "txtExportNameFilter",
            "Value": ""
        },
        {
            "Name": "chkAddObjectType",
            "Value": true
        },
        {
            "Name": "chkExportAssignments",
            "Value": true
        },
        {
            "Name": "chkAddCompanyName",
            "Value": true
        },
        {
            "Name": "chkExportScript",
            "Value": true
        },
        {
            "Name": "chkExportApplicationFile",
            "Value": false
        },
        {
            "Name": "ObjectTypes",
            "Type": "Custom",
            "ObjectTypes": [
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
            ]
        }
    ]
}
```

### BulkImport.json
Controls how imports are handled:
```json
{
  "BulkImport": [
    {
      "Name": "txtImportPath",
      "Value": ".\\intune-backup"
    },
    {
      "Name": "txtImportNameFilter",
      "Value": " - Restore"
    },
    {
      "Name": "chkAddObjectType",
      "Value": true
    },
    {
      "Name": "chkImportScopes",
      "Value": false
    },
    {
      "Name": "chkImportAssignments",
      "Value": true
    },
    {
      "Name": "chkReplaceDependencyIDs",
      "Value": true
    },
    {
      "Name": "cbImportType",
      "Value": "skipIfExist"
    },
    {
      "Name": "cbImportCAState",
      "Value": "disabled"
    },
    {
      "Name": "ObjectTypes",
      "Type": "Custom",
      "ObjectTypes": [
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
      ]
    }
  ]
}


```

### Generate Custom Configurations
Use the interactive configuration generator:
```powershell
.\Generate-BulkConfig.ps1
```

## 🎯 Use Cases

### Daily Tenant Snapshots
- Automated daily backups via GitHub Actions
- Version-controlled configuration history
- Quick rollback capabilities

### Environment Promotion
```powershell
# Export from DEV tenant
.\IntuneManagement-Local.ps1 -Action Backup -TenantId "dev-tenant-id" -AppId "app-id" -Secret "secret"

# Import to PROD tenant
.\IntuneManagement-Local.ps1 -Action Restore -TenantId "prod-tenant-id" -AppId "app-id" -Secret "secret"
```

### Disaster Recovery
1. Restore from latest backup in `intune-backup/` directory
2. Use dry run to validate before applying changes
3. Selective restore of specific policy types

### Configuration Testing
1. Use **dry run mode** in GitHub Actions
2. Validate configurations without applying changes
3. Test import behavior safely

## 🔧 Advanced Usage

### Selective Object Type Export
```powershell
# Only export specific object types
# Modify BulkExport.json ObjectTypes array or use parameterized workflow
```

### Custom Import Behavior
- `skipIfExist`: Skip if policy already exists
- `overwrite`: Replace existing policies
- `append`: Add new policies only

### Conditional Access Handling
- `disabled`: Import CA policies in disabled state
- `enabled`: Import CA policies as enabled
- `enabledForReportingButNotEnforced`: Report-only mode

## 🚨 Important Notes

### Security Considerations
- Store Azure credentials securely in GitHub Secrets
- Use service principal with minimal required permissions
- Regularly rotate client secrets
- Review export contents before committing to version control

### Best Practices
- Always test imports in non-production environments first
- Use dry run mode to validate configurations
- Maintain separate configurations for different tenants
- Regular backup schedule (daily recommended)
- Document any custom configurations or filters

### Limitations
- Some settings may not be exportable/importable
- Tenant-specific GUIDs will be different between environments
- Some dependencies may need manual configuration
- Rate limiting may affect large tenant operations

## 🐛 Troubleshooting

### Common Issues

**PowerShell Execution Policy**
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Authentication Failures**
- Verify Azure AD app permissions
- Check client secret expiration
- Confirm tenant ID is correct

### Debug Mode
Add `-Verbose` parameter to scripts for detailed logging:
```powershell
.\IntuneManagement-Local.ps1 -Action Backup -TenantId "tenant" -AppId "app" -Secret "secret" -Verbose
```

## 📚 Additional Resources

- [IntuneManagement Tool](https://github.com/Micke-K/IntuneManagement) - Underlying backup/restore engine
- [Microsoft Graph API Documentation](https://docs.microsoft.com/en-us/graph/api/resources/intune-graph-overview)
- [Azure AD App Registration Guide](https://docs.microsoft.com/en-us/azure/active-directory/develop/quickstart-register-app)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## ⚠️ Disclaimer

This tool is provided as-is. Always test in non-production environments first. The authors are not responsible for any data loss or configuration issues that may arise from using this tool.
