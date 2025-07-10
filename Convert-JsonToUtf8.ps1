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
                    Write-Host "Processing: $($file.FullName)" -ForegroundColor White
                    
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
                                Write-Host "  Current encoding: $currentEncoding - SKIPPED" -ForegroundColor Green
                                $skippedCount++
                                continue
                            } else {
                                $currentEncoding = "Likely ANSI/ASCII"
                            }
                        } catch {
                            $currentEncoding = "Unknown/Binary"
                        }
                    }
                    
                    Write-Host "  Current encoding: $currentEncoding" -ForegroundColor Gray
                    
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
                        Write-Host "  Backup created: $backupPath" -ForegroundColor Blue
                    }
                    
                    # Write content as UTF-8 without BOM
                    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                    [System.IO.File]::WriteAllText($file.FullName, $content, $utf8NoBom)
                    
                    Write-Host "  Successfully converted to UTF-8 without BOM" -ForegroundColor Green
                    $convertedCount++
                } catch {
                    Write-Error "  Error processing file: $($_.Exception.Message)"
                    $errorCount++
                }
                
                Write-Host ""
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

# If script is run directly, execute the function
if ($MyInvocation.InvocationName -ne '.') {
    Convert-JsonToUtf8 @args
}
