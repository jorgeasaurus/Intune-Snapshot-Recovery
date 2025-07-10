# App and version we are looking for
$AppDisplayName = "Parallels Tools" # Example: "Microsoft Visual Studio Code"
$AppDisplayVersion = "19.4.1.54985" # Example: "1.84.2"

function PSIntuneWinDetection {
    param($SearchFor, [switch]$Wow6432Node, [switch]$userContext)

    class UninstallInfo {
        [string]$GUID
        [string]$Publisher
        [string]$DisplayName
        [string]$DisplayVersion
        [string]$InstallLocation
        [string]$InstallDate
        [string]$UninstallString
        [string]$Wow6432Node
        [string]$UserContext
    }

    function Get-UninstallInfo {
        param($Path, [string]$Node = 'No', [string]$UserCtx = 'No')
        Get-ChildItem $Path | ForEach-Object {
            $info = [UninstallInfo]::new()
            $info.GUID = $_.pschildname
            $info.Publisher = $_.GetValue('Publisher')
            $info.DisplayName = $_.GetValue('DisplayName')
            $info.DisplayVersion = $_.GetValue('DisplayVersion')
            $info.InstallLocation = $_.GetValue('InstallLocation')
            $info.InstallDate = $_.GetValue('InstallDate')
            $info.UninstallString = $_.GetValue('UninstallString')
            $info.Wow6432Node = $Node
            $info.UserContext = $UserCtx
            $info
        }
    }

    $results = [System.Collections.Generic.List[UninstallInfo]]::new()

    # Default registry path
    [UninstallInfo[]]$defaultInfo = Get-UninstallInfo 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    $results.AddRange($defaultInfo)

    # Additional paths based on switches
    if ($Wow6432Node) {
        [UninstallInfo[]]$wow6432Info = Get-UninstallInfo 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall' 'Yes'
        $results.AddRange($wow6432Info)
    }
    if ($userContext) {
        [UninstallInfo[]]$userInfo = Get-UninstallInfo 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' 'No' 'Yes'
        $results.AddRange($userInfo)
    }

    # Sorting and filtering results
    $results | Sort-Object DisplayName | Where-Object { $_.DisplayName -match $SearchFor }
}

# Usage example:
$appDetected = PSIntuneWinDetection -SearchFor $AppDisplayName -Wow6432Node -userContext | Where-Object { $_.DisplayVersion -eq $AppDisplayVersion }

if ($appDetected) {
    return "installed"
}