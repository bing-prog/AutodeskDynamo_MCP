param(
    [string[]]$TargetDynamoVersions = @()
)

$ErrorActionPreference = "Stop"

# ========================================
# Step 0: Convert Config
# ========================================
Write-Host "`n[0/4] Updating Config..." -ForegroundColor Cyan
$UpdateConfigScript = Join-Path $PSScriptRoot "scripts\update_config.py"
if (Test-Path $UpdateConfigScript) {
    python $UpdateConfigScript
    if ($LASTEXITCODE -ne 0) { 
        Write-Warning "Config conversion failed, using existing mcp_config.json"
    }
}
else {
    Write-Host "   WARNING: update_config.py not found, skipping config update" -ForegroundColor Yellow
}

# Configuration
$ProjectFile = "DynamoViewExtension\DynamoMCPListener.csproj"
$PackageName = "MCP_Listener_Package"
$PackageSourceDir = Join-Path $PSScriptRoot $PackageName
$PackageBinDir = Join-Path $PackageSourceDir "bin"

function Get-InstalledRevitDynamoMap {
    $rows = @()
    foreach ($year in 2020..2027) {
        $dynamoCorePath = "C:\Program Files\Autodesk\Revit $year\AddIns\DynamoForRevit\DynamoCore.dll"
        if (Test-Path $dynamoCorePath) {
            $versionInfo = (Get-Item $dynamoCorePath).VersionInfo
            $rows += [pscustomobject]@{
                RevitYear = $year
                DynamoVersion = $versionInfo.ProductVersion
                DynamoMajorMinor = ([version]$versionInfo.ProductVersion).ToString(2)
                Path = $dynamoCorePath
            }
        }
    }

    return $rows
}

function Get-BuildProfile {
    param(
        [string]$DynamoVersion
    )

    switch -Regex ($DynamoVersion) {
        '^2\.3(\.\d+)?$' {
            return [pscustomobject]@{
                DynamoVersion = $DynamoVersion
                TargetFramework = 'net48'
                PackageVersion = '2.3.0.5885'
                OutputSubdir = 'dyn-2.3'
                EngineVersion = '2.3.0.0'
            }
        }
        '^2\.6(\.\d+)?$' {
            return [pscustomobject]@{
                DynamoVersion = $DynamoVersion
                TargetFramework = 'net48'
                PackageVersion = '2.6.1.8786'
                OutputSubdir = 'dyn-2.6'
                EngineVersion = '2.6.0.0'
            }
        }
        '^2\.10(\.\d+)?$' {
            return [pscustomobject]@{
                DynamoVersion = $DynamoVersion
                TargetFramework = 'net48'
                PackageVersion = '2.10.1.4002'
                OutputSubdir = 'dyn-2.10'
                EngineVersion = '2.10.0.0'
            }
        }
        '^2\.13(\.\d+)?$' {
            return [pscustomobject]@{
                DynamoVersion = $DynamoVersion
                TargetFramework = 'net48'
                PackageVersion = '2.13.1.3891'
                OutputSubdir = 'dyn-2.13'
                EngineVersion = '2.13.0.0'
            }
        }
        '^2\.19(\.\d+)?$' {
            return [pscustomobject]@{
                DynamoVersion = $DynamoVersion
                TargetFramework = 'net48'
                PackageVersion = '2.19.3.6394'
                OutputSubdir = 'dyn-2.19'
                EngineVersion = '2.19.0.0'
            }
        }
        '^3\.0(\.\d+)?$' {
            return [pscustomobject]@{
                DynamoVersion = $DynamoVersion
                TargetFramework = 'net8.0-windows'
                PackageVersion = '3.0.3.7597'
                OutputSubdir = 'dyn-3.0'
                EngineVersion = '3.0.0.0'
            }
        }
        '^3\.(\d+)(\.\d+)?$' {
            return [pscustomobject]@{
                DynamoVersion = $DynamoVersion
                TargetFramework = 'net8.0-windows'
                PackageVersion = '3.4.1.7055'
                OutputSubdir = 'dyn-3.4'
                EngineVersion = '3.4.0.0'
            }
        }
        '^4\.(\d+)(\.\d+)?$' {
            return [pscustomobject]@{
                DynamoVersion = $DynamoVersion
                TargetFramework = 'net10.0-windows'
                PackageVersion = '4.0.2.3852'
                OutputSubdir = 'dyn-4.0'
                EngineVersion = '4.0.0.0'
            }
        }
        default {
            throw "Unsupported Dynamo version for MCP Listener deployment: $DynamoVersion"
        }
    }
}

function Get-VersionKey {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VersionText
    )

    if ($VersionText -match '^\d+$') {
        return "$VersionText.0"
    }

    try {
        return ([version]$VersionText).ToString(2)
    }
    catch {
        if ($VersionText -match '^(\d+\.\d+)') {
            return $Matches[1]
        }

        return $VersionText
    }
}

function Get-BuildVersionKey {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VersionText
    )

    $versionKey = Get-VersionKey -VersionText $VersionText

    switch -Regex ($versionKey) {
        '^27\.0(\.\d+)?$' { return '4.0' }
        default { return $versionKey }
    }
}

function New-PackageManifest {
    param(
        [string]$EngineVersion
    )

    return @{
        name = 'MCP Listener'
        version = '1.0.0'
        description = 'Listens for MCP commands from Python Server'
        engine_version = $EngineVersion
        group = 'MCP'
        keywords = @('mcp', 'ai')
        dependencies = @()
        license = 'Apache-2.0'
        view_extensions = @(
            @{
                assembly_name = 'bin\\DynamoMCPListener.dll'
                type_name = 'DynamoMCPListener.ViewExtension'
            }
        )
    } | ConvertTo-Json -Depth 5
}

# Determine Dynamo Packages Path (Trying standard locations)
$AppDataDynamo = "$env:AppData\Dynamo\Dynamo Revit"

function Get-DetectedDynamoVersions {
    if (-not (Test-Path $AppDataDynamo)) {
        return @()
    }

    return Get-ChildItem $AppDataDynamo -Directory |
        Where-Object { $_.Name -match "^\d+(\.\d+)+$" } |
        Sort-Object {
            try {
                [version]$_.Name
            }
            catch {
                [version]'0.0'
            }
        } -Descending
}

function Get-AvailableDeploymentTargets {
    param(
        [array]$DetectedVersions,
        [array]$InstalledRevitMap
    )

    $targetsByName = @{}

    foreach ($versionDir in $DetectedVersions) {
        $versionKey = Get-BuildVersionKey -VersionText $versionDir.Name
        if (-not $targetsByName.ContainsKey($versionKey)) {
            $targetsByName[$versionKey] = [pscustomobject]@{
                Name = $versionKey
                AppDataVersionDir = $versionDir.FullName
                Source = "AppData ($($versionDir.Name))"
            }
        }
    }

    foreach ($mapping in $InstalledRevitMap) {
        $versionKey = Get-BuildVersionKey -VersionText $mapping.DynamoMajorMinor
        if (-not $targetsByName.ContainsKey($versionKey)) {
            $targetsByName[$versionKey] = [pscustomobject]@{
                Name = $versionKey
                AppDataVersionDir = Join-Path $AppDataDynamo $versionKey
                Source = "Revit $($mapping.RevitYear)"
            }
        }
    }

    return $targetsByName.Values | Sort-Object {
        try {
            [version]$_.Name
        }
        catch {
            [version]'0.0'
        }
    } -Descending
}

$DetectedVersions = Get-DetectedDynamoVersions
$InstalledRevitMap = Get-InstalledRevitDynamoMap
$AvailableTargets = Get-AvailableDeploymentTargets -DetectedVersions $DetectedVersions -InstalledRevitMap $InstalledRevitMap

if ($AvailableTargets.Count -eq 0) {
    Write-Error "Could not find any installed Revit or Dynamo versions for deployment."
}

if ($InstalledRevitMap.Count -gt 0) {
    Write-Host "Detected Revit -> Dynamo mapping:" -ForegroundColor Cyan
    $InstalledRevitMap | Select-Object RevitYear, DynamoVersion, DynamoMajorMinor | Format-Table -AutoSize
}

if ($TargetDynamoVersions.Count -gt 0) {
    $RequestedVersionKeys = $TargetDynamoVersions | ForEach-Object { Get-VersionKey -VersionText ([string]$_) } | Select-Object -Unique
    $SelectedVersions = $AvailableTargets | Where-Object { $RequestedVersionKeys -contains $_.Name }
    if ($SelectedVersions.Count -eq 0) {
        Write-Error "None of the requested Dynamo versions were found: $($RequestedVersionKeys -join ', ')"
    }
}
else {
    $SelectedVersions = $AvailableTargets
}

Write-Host "Targeting Dynamo Versions: $($SelectedVersions.Name -join ', ')"
Write-Host "Detected Dynamo Versions: $($DetectedVersions.Name -join ', ')"
Write-Host "Available Deployment Targets: $($AvailableTargets.Name -join ', ')"

$SupportedVersions = @()
$SkippedVersions = @()
$BuildProfiles = @()

foreach ($Version in $SelectedVersions) {
    try {
        $Profile = Get-BuildProfile -DynamoVersion $Version.Name
        $SupportedVersions += $Version
        $BuildProfiles += $Profile
    }
    catch {
        $SkippedVersions += [pscustomobject]@{
            DynamoVersion = $Version.Name
            Reason = $_.Exception.Message
        }
    }
}

if ($SkippedVersions.Count -gt 0) {
    Write-Warning "Skipping unsupported Dynamo versions: $($SkippedVersions.DynamoVersion -join ', ')"
    foreach ($Skip in $SkippedVersions) {
        Write-Host "   - $($Skip.DynamoVersion): $($Skip.Reason)" -ForegroundColor Yellow
    }
}

if ($SupportedVersions.Count -eq 0) {
    Write-Error "No supported Dynamo versions found for deployment."
}

Write-Host "Supported Dynamo Versions: $($SupportedVersions.Name -join ', ')" -ForegroundColor Green

$BuildProfiles = $BuildProfiles | Sort-Object OutputSubdir -Unique

# 1. Build project
Write-Host "`n[1/4] Building Project..."
$DotNetSdkAvailable = $false
 $DotNetExe = $null
$DotNetCommand = Get-Command dotnet -ErrorAction SilentlyContinue
if ($DotNetCommand) {
    $DotNetExe = $DotNetCommand.Source
}
if (-not $DotNetExe -and (Test-Path "C:\Program Files\dotnet\dotnet.exe")) {
    $DotNetExe = "C:\Program Files\dotnet\dotnet.exe"
}
try {
    if ($DotNetExe) {
        $SdkList = & $DotNetExe --list-sdks 2>$null
    }
    else {
        $SdkList = & dotnet --list-sdks 2>$null
    }
    if ($LASTEXITCODE -eq 0 -and $SdkList) {
        $DotNetSdkAvailable = $true
    }
}
catch {
    $DotNetSdkAvailable = $false
}

if ($DotNetSdkAvailable) {
    $AvailableSdkMajors = @($SdkList | ForEach-Object {
        if ($_ -match '^(\d+)\.') {
            [int]$Matches[1]
        }
    } | Select-Object -Unique)

    foreach ($BuildProfile in $BuildProfiles) {
        Write-Host "   - Building for Dynamo $($BuildProfile.DynamoVersion) ($($BuildProfile.TargetFramework), package $($BuildProfile.PackageVersion))" -ForegroundColor Cyan

        if ($BuildProfile.TargetFramework -match '^net(\d+)\.0-windows$') {
            $RequiredSdkMajor = [int]$Matches[1]
            if ($AvailableSdkMajors -notcontains $RequiredSdkMajor) {
                throw "Build for Dynamo $($BuildProfile.DynamoVersion) requires .NET SDK $RequiredSdkMajor.x because target framework is $($BuildProfile.TargetFramework). Installed SDKs: $($SdkList -join ', ')"
            }
        }

        $BuildArgs = @(
            'build'
            $ProjectFile
            '-c'
            'Release'
            '-f'
            $BuildProfile.TargetFramework
            '-p:TargetFrameworks=' + $BuildProfile.TargetFramework
            '-p:DynamoPackageVersion=' + $BuildProfile.PackageVersion
            '-p:CustomOutputSubdir=' + $BuildProfile.OutputSubdir
        )

        if ($DotNetExe) {
            & $DotNetExe @BuildArgs
        }
        else {
            dotnet @BuildArgs
        }
        if ($LASTEXITCODE -ne 0) { throw "Build failed for Dynamo $($BuildProfile.DynamoVersion)" }
    }
}
else {
    Write-Warning "   - No .NET SDK found. Skipping build and using existing Release artifacts."
    if (-not (Test-Path $PackageBinDir)) {
        throw "Existing Release artifacts not found. Cannot continue without .NET SDK."
    }
}

# 2. Validate build outputs
Write-Host "`n[2/4] Validating Build Outputs..."
foreach ($BuildProfile in $BuildProfiles) {
    $BuildOutputDir = Join-Path $PSScriptRoot "DynamoViewExtension\bin\Release\$($BuildProfile.OutputSubdir)"
    if (-not (Test-Path $BuildOutputDir)) {
        throw "Build output not found for Dynamo $($BuildProfile.DynamoVersion): $BuildOutputDir"
    }
    Write-Host "   - Build output ready: $BuildOutputDir" -ForegroundColor Green
}

# 3. Deploy to Dynamo (all selected versions)
Write-Host "`n[3/4] Deploying to Dynamo Packages..."

foreach ($Version in $SupportedVersions) {
    $DynamoPackagesDir = Join-Path $Version.AppDataVersionDir 'packages'
    $TargetPackageDir = Join-Path $DynamoPackagesDir "MCP Listener"
    $BuildProfile = Get-BuildProfile -DynamoVersion $Version.Name
    $BuildOutputDir = Join-Path $PSScriptRoot "DynamoViewExtension\bin\Release\$($BuildProfile.OutputSubdir)"
    $TargetBinDir = Join-Path $TargetPackageDir 'bin'

    Write-Host "   - Deploying to Dynamo $($Version.Name) [$($Version.Source)]" -ForegroundColor Cyan

    if (-not (Test-Path $DynamoPackagesDir)) {
        New-Item -ItemType Directory -Path $DynamoPackagesDir -Force | Out-Null
        Write-Host "     Created packages directory: $DynamoPackagesDir" -ForegroundColor Cyan
    }

    if (Test-Path $TargetPackageDir) {
        Remove-Item $TargetPackageDir -Recurse -Force
    }

    Copy-Item $PackageSourceDir -Destination $TargetPackageDir -Recurse -Force

    if (Test-Path $TargetBinDir) {
        Remove-Item $TargetBinDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $TargetBinDir -Force | Out-Null
    Copy-Item "$BuildOutputDir\*" -Destination $TargetBinDir -Force -Recurse

    if (Test-Path "$TargetBinDir\DynamoMCPListener.deps.json") {
        Remove-Item "$TargetBinDir\DynamoMCPListener.deps.json" -Force
        Write-Host "     Removed .deps.json for Dynamo $($Version.Name)" -ForegroundColor DarkGray
    }

    $ConflictDlls = @("DynamoServices.dll", "DynamoCore.dll", "DynamoInstallTask.dll")
    foreach ($dll in $ConflictDlls) {
        $dllPath = Join-Path $TargetBinDir $dll
        if (Test-Path $dllPath) {
            Remove-Item $dllPath -Force
            Write-Host "     Removed conflicting DLL: $dll" -ForegroundColor DarkGray
        }
    }

    $PackageManifest = New-PackageManifest -EngineVersion $BuildProfile.EngineVersion
    Set-Content -Path (Join-Path $TargetPackageDir 'pkg.json') -Value $PackageManifest -Encoding UTF8

    # UNBLOCK FILES (Security Fix)
    Get-ChildItem -Path $TargetPackageDir -Recurse | Unblock-File
}

# 4. Deploy Config
Write-Host "`n[4/4] Deploying Config & Updating ViewExtension Paths..." -ForegroundColor Cyan

# Deploy mcp_config.json to package directory
$configSource = Join-Path $PSScriptRoot "mcp_config.json"

if (Test-Path $configSource) {
    foreach ($Version in $SupportedVersions) {
        $configDest = Join-Path $Version.AppDataVersionDir 'packages\MCP Listener\mcp_config.json'
        Copy-Item $configSource $configDest -Force
    }
    Write-Host "   - Config file deployed to supported versions: mcp_config.json" -ForegroundColor Green
}
else {
    Write-Warning "   - Config file not found: $configSource"
}

# --- CLEANUP STRATEGY: Remove Legacy XMLs and rely on valid pkg.json ---
# We previously broadcasted XMLs everywhere. This creates "Double Loading" risks if pkg.json also works.
# Since we fixed pkg.json path ("bin\dll"), we should CLEANUP the XMLs to be safe.

$XmlFileName = "DynamoMCPListener_ViewExtensionDefinition.xml"

Write-Host "`n[4.5/4] Cleaning up Legacy XML Registrations..."

# Scan for all Dynamo versions
$AppDataDynamo = "$env:AppData\Dynamo"
$Products = Get-ChildItem -Path $AppDataDynamo -Directory

foreach ($Product in $Products) {
    # Check for Versions starting with 3.
    $Versions = Get-ChildItem -Path $Product.FullName -Directory
    
    foreach ($Ver in $Versions) {
        $GlobalExtDir = Join-Path $Ver.FullName "viewExtensions"
        if (Test-Path $GlobalExtDir) {
            $TargetXml = Join-Path $GlobalExtDir $XmlFileName
            if (Test-Path $TargetXml) {
                Remove-Item $TargetXml -Force
                Write-Host "      [-] Removed legacy XML from: $($Product.Name) \$($Ver.Name)" -ForegroundColor Yellow
            }
        }
    }
}

# Note: We KEEP the Package-Level XML because it's required for some Dynamo versions.
# The previous broadcasted XMLs in global folders are still removed to prevent conflicts.

Write-Host "`nSUCCESS: Package deployed!"
Write-Host "You can now open Dynamo."
