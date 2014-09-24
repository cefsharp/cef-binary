param(
    [ValidateSet("vs2013", "vs2012", "vs2010", "nupkg")]
    [Parameter(Position = 0)] 
    [string] $Target = "nupkg",
    [Parameter(Position = 1)]
    [string] $Version = "3.1750.1738-pre0"
)

Import-Module BitsTransfer

$WorkingDir = split-path -parent $MyInvocation.MyCommand.Definition
$ToolsDir = Join-Path $WorkingDir .tools

$Cef = Join-Path $WorkingDir 'cef'
$CefInclude = Join-Path $Cef 'include'
$Cef32 = Join-Path $WorkingDir 'cef_binary_3.y.z_windows32'
$Cef32vcx =Join-Path $Cef32 'libcef_dll_wrapper.vcxproj'
$Cef64 = Join-Path $WorkingDir  'cef_binary_3.y.z_windows64'
$Cef64vcx =Join-Path $Cef64 'libcef_dll_wrapper.vcxproj'

$Cef32Url = "http://software.odinkapital.no/opensource/cef/cef_binary_3.1750.1738_windows32.zip"
$Cef64Url = "http://software.odinkapital.no/opensource/cef/cef_binary_3.1750.1738_windows64.zip"

# https://github.com/jbake/Powershell_scripts/blob/master/Invoke-BatchFile.ps1
function Invoke-BatchFile 
{
   param(
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Path, 
        [Parameter(Position = 1, Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Parameters
   )

   $tempFile = [IO.Path]::GetTempFileName()  

   cmd.exe /c " `"$Path`" $Parameters && set > `"$tempFile`" " 

   Get-Content $tempFile | Foreach-Object {   
       if ($_ -match "^(.*?)=(.*)$")  
       { 
           Set-Content "env:\$($matches[1])" $matches[2]  
       } 
   }  

   Remove-Item $tempFile
}

function Write-Diagnostic 
{
    param(
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true)]
        [string] $Message
    )

    Write-Host
    Write-Host $Message -ForegroundColor Green
    Write-Host
}

function Die 
{
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        [string] $Message
    )

    Write-Host
	Write-Error $Message 
	exit 1

}

function Warn 
{
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        [string] $Message
    )

    Write-Host
	Write-Host $Message -ForegroundColor Yellow
	Write-Host

}

function TernaryReturn 
{
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        [bool] $Yes,
        [Parameter(Position = 1, ValueFromPipeline = $true)]
        $Value,
        [Parameter(Position = 2, ValueFromPipeline = $true)]
        $Value2
    )

    if($Yes) {
        return $Value
    }
    
    $Value2

}

function Unzip 
{
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        [string] $Filename,
        [Parameter(Position = 1, ValueFromPipeline = $true)]
        [string] $ExtractToDestination
    )
    $ShellApp = New-Object -Com shell.application
    $Zip = $ShellApp.namespace($Filename)
    if(-not (Test-Path $ExtractToDestination)) {
        New-Item -ItemType Directory -Path $ExtractToDestination | Out-Null
    }
    $Destination = $ShellApp.namespace($ExtractToDestination)
    $Destination.Copyhere($Zip.items())
}

function Bootstrap
{
  param()
     
  Write-Diagnostic "Bootstrapping"

  if(-not (Test-Path $ToolsDir)) {
    New-Item -ItemType Directory -Path $ToolsDir | Out-Null
  }

  if(-not (Test-Path $Cef32vcx)) {
    Write-Output "Downloading $Cef32Url"
    Start-BitsTransfer $Cef32Url $ToolsDir\cef_binary_windows32.zip
    Write-Output "Extracting..."
    Unzip $ToolsDir\cef_binary_windows32.zip $Cef32
  }

  if(-not (Test-Path $Cef64vcx)) {
    Write-Output "Downloading $Cef64Url"
    Start-BitsTransfer $Cef64Url $ToolsDir\cef_binary_windows64.zip
    Write-Output "Extracting..."
    Unzip $ToolsDir\cef_binary_windows64.zip $Cef64
  }

  if (Test-Path($Cef)) {
    Remove-Item $Cef -Recurse | Out-Null
  }

  # Copy include files
  Copy-Item $Cef64\include $CefInclude -Recurse | Out-Null

  # Create default directory structure
  md 'cef\win32' | Out-Null
  md 'cef\win32\debug' | Out-Null
  md 'cef\win32\debug\VS2010' | Out-Null
  md 'cef\win32\debug\VS2012' | Out-Null
  md 'cef\win32\debug\VS2013' | Out-Null
  md 'cef\win32\release' | Out-Null
  md 'cef\win32\release\VS2010' | Out-Null
  md 'cef\win32\release\VS2012' | Out-Null
  md 'cef\win32\release\VS2013' | Out-Null
  md 'cef\x64' | Out-Null
  md 'cef\x64\debug' | Out-Null
  md 'cef\x64\debug\VS2010' | Out-Null
  md 'cef\x64\debug\VS2012' | Out-Null
  md 'cef\x64\debug\VS2013' | Out-Null
  md 'cef\x64\release' | Out-Null 
  md 'cef\x64\release\VS2010' | Out-Null
  md 'cef\x64\release\VS2012' | Out-Null 
  md 'cef\x64\release\VS2013' | Out-Null

}

function Msvs 
{
    param(
        [ValidateSet('v100', 'v110', 'v120')]
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        [string] $Toolchain, 

        [Parameter(Position = 1, ValueFromPipeline = $true)]
        [ValidateSet('Debug', 'Release')]
        [string] $Configuration, 

        [Parameter(Position = 2, ValueFromPipeline = $true)]
        [ValidateSet('x86', 'x64')]
        [string] $Platform
    )

    Write-Diagnostic "Targeting $Toolchain using configuration $Configuration on platform $Platform"

    $PlatformTarget = $null
    $VisualStudioVersion = $null
    $VXXCommonTools = $null

    switch -Exact ($Toolchain) {
        'v100' {
            $PlatformTarget = '4.0'
            $VisualStudioVersion = '10.0'
            $VXXCommonTools = Join-Path $env:VS100COMNTOOLS '..\..\vc'
        }
        'v110' {
            $PlatformTarget = '4.0'
            $VisualStudioVersion = '11.0'
            $VXXCommonTools = Join-Path $env:VS110COMNTOOLS '..\..\vc'
        }
        'v120' {
            $PlatformTarget = '12.0'
            $VisualStudioVersion = '12.0'
            $VXXCommonTools = Join-Path $env:VS120COMNTOOLS '..\..\vc'
        }
    }

    if ($VXXCommonTools -eq $null -or (-not (Test-Path($VXXCommonTools)))) {
        Die 'Error unable to find any visual studio environment'
    }

    $CefProject = TernaryReturn ($Platform -eq 'x86') $Cef32vcx $Cef64vcx
    if($Platform -eq 'x64') {
        $RuntimeLibrary = TernaryReturn ($Configuration -eq 'Debug') 'MultiThreadedDebugDLL' 'MultiThreadedDLL'
    } else {
        $RuntimeLibrary = TernaryReturn ($Configuration -eq 'Debug') 'MultiThreadedDebugDLL' 'MultiThreaded'
    }

    $VCVarsAll = Join-Path $VXXCommonTools vcvarsall.bat
    if (-not (Test-Path $VCVarsAll)) {
        Die "Unable to find $VCVarsAll"
    }

    $VCXProj = $Cef32vcx
    if($Platform -eq 'x64') {
        $VCXProj = $Cef64vcx
    }

    # Only configure build environment once
    if($env:CEFSHARP_BUILD_IS_BOOTSTRAPPED -eq $null) {
        Invoke-BatchFile $VCVarsAll $Platform
        $env:CEFSHARP_BUILD_IS_BOOTSTRAPPED = $true
    }

    $Arch = TernaryReturn ($Platform -eq 'x64') 'x64' 'win32'

    $Arguments = @(
        "$CefProject",
        "/t:rebuild",
        "/p:VisualStudioVersion=$VisualStudioVersion",
        "/p:RuntimeLibrary=$RuntimeLibrary",
        "/p:Configuration=$Configuration",
        "/p:PlatformTarget=$PlatformTarget",
        "/p:PlatformToolset=$Toolchain",
        "/p:Platform=$Arch",
        "/p:PreferredToolArchitecture=$Arch"
        "/p:ConfigurationType=StaticLibrary"
    )

    $StartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $StartInfo.FileName = "msbuild.exe"
    $StartInfo.Arguments = $Arguments

    $StartInfo.EnvironmentVariables.Clear()

    Get-ChildItem -Path env:* | ForEach-Object {
        $StartInfo.EnvironmentVariables.Add($_.Name, $_.Value)
    }

    $StartInfo.UseShellExecute = $false
    $StartInfo.CreateNoWindow = $false

    $Process = New-Object System.Diagnostics.Process
    $Process.StartInfo = $startInfo
    $Process.Start() 
    $Process.WaitForExit()

    if($Process.ExitCode -ne 0) {
        Die "Build failed"
    }

    CreateCefSdk $Toolchain $Configuration $Platform
}

function VSX 
{
    param(
        [ValidateSet('v100', 'v110', 'v120')]
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        [string] $Toolchain
    )

    if($Toolchain -eq 'v120' -and $env:VS120COMNTOOLS -eq $null) {
        Warn "Toolchain $Toolchain is not installed on your development machine, skipping build."
        Return
    }

    if($Toolchain -eq 'v110' -and $env:VS110COMNTOOLS -eq $null) {
        Warn "Toolchain $Toolchain is not installed on your development machine, skipping build."
        Return
    }

    if($Toolchain -eq 'v100' -and $env:VS100COMNTOOLS -eq $null) {
        Warn "Toolchain $Toolchain is not installed on your development machine, skipping build."
        Return
    }

    Write-Diagnostic "Starting to build targeting toolchain $Toolchain"

    Msvs "$Toolchain" 'Debug' 'x86'
    Msvs "$Toolchain" 'Release' 'x86'
    Msvs "$Toolchain" 'Debug' 'x64'
    Msvs "$Toolchain" 'Release' 'x64'

    Write-Diagnostic "Finished build targeting toolchain $Toolchain"
}

function CreateCefSdk 
{
    param(
        [ValidateSet('v100', 'v110', 'v120')]
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        [string] $Toolchain, 

        [Parameter(Position = 1, ValueFromPipeline = $true)]
        [ValidateSet('Debug', 'Release')]
        [string] $Configuration, 

        [Parameter(Position = 2, ValueFromPipeline = $true)]
        [ValidateSet('x86', 'x64')]
        [string] $Platform
    )

    Write-Diagnostic "Creating sdk for $Toolchain"

    $VisualStudioVersion = $null
    if($Toolchain -eq "v120") {
        $VisualStudioVersion = "VS2013"
    } elseif($Toolchain -eq "v110") {
        $VisualStudioVersion = "VS2012"
    } else {
        $VisualStudioVersion = "VS2010"
    }

    $Arch = TernaryReturn ($Platform -eq 'x64') 'x64' 'win32'
    $CefArchDir = TernaryReturn ($Platform -eq 'x64') $Cef64 $Cef32

    # cef_binary_3.y.z_windows32\out\debug\lib -> cef\win32\debug\vs2013
    Copy-Item $CefArchDir\out\$Configuration\lib\libcef_dll_wrapper.lib $Cef\$Arch\$Configuration\$VisualStudioVersion | Out-Null

    # cef_binary_3.y.z_windows32\debug -> cef\win32\debug
    Copy-Item $CefArchDir\$Configuration\libcef.lib $Cef\$Arch\$Configuration | Out-Null

}

function Nupkg
{
    $nuget = Join-Path $env:LOCALAPPDATA .\nuget\NuGet.exe
    if(-not (Test-Path $nuget)) {
        Die "Please install nuget. More information available at: http://docs.nuget.org/docs/start-here/installing-nuget"
    }

    Write-Diagnostic "Building nuget package"

    # Save content as UTF8 without adding BOM
    $Filename = Resolve-Path ".\nuget\cef.sdk.props"
    $Text = (Get-Content $Filename) -replace '<CefSdkVer>.*<\/CefSdkVer>', "<CefSdkVer>cef.sdk.$Version</CefSdkVer>"
    [System.IO.File]::WriteAllLines($Filename, $Text)

    # Build packages
    . $nuget pack nuget\cef.redist.nuspec -NoPackageAnalysis -Version $Version -OutputDirectory nuget
    . $nuget pack nuget\cef.sdk.nuspec -NoPackageAnalysis -Version $Version -OutputDirectory nuget
}

Bootstrap

switch -Exact ($Target) {
    "nupkg" {
        VSX v120
        VSX v110
        #VSX v100
        Nupkg
    }
    "vs2013" {
        VSX v120
    }
    "vs2012" {
        VSX v110
    }
    "vs2010" {
        VSX v100
    }
}