#requires -Version 3

param(
    [ValidateSet("vs2012", "vs2013", "vs2015", "vs2017", "nupkg", "nupkg-only")]
    [Parameter(Position = 0)]
    [string] $Target = "nupkg",

    [ValidateSet("none", "download", "local")]
    [Parameter(Position = 1)]
    [string] $DownloadBinary = "download",

    [Parameter(Position = 2)]
    # absolute or relative path to directory containing cef binaries archives (used if DownloadBinary = local)
    [string] $CefBinaryDir = "../cefsource/chromium/src/cef/binary_distrib/",

    [Parameter(Position = 3)]
    $CefVersion = "3.3239.1700.g385b2d4",

    [ValidateSet("tar.bz2","zip","7z")]
    [Parameter()]
    [string] $Extension = "tar.bz2",
    [Switch] $NoDebugBuild
)
Set-StrictMode -version latest
$ErrorActionPreference = "Stop";
$Extension = $Extension.ToLower();
Function WriteException($exp){
    write-host "Caught an exception:" -ForegroundColor Yellow -NoNewline;
    write-host " $($exp.Exception.Message)" -ForegroundColor Red;
    write-host "`tException Type: $($exp.Exception.GetType().FullName)";
    $stack = $exp.ScriptStackTrace;
    $stack = $stack.replace("`n","`n`t");
    write-host "`tStack Trace: $stack";
    throw $exp;
}
try{
$WorkingDir = split-path -parent $MyInvocation.MyCommand.Definition;
if ($CefVersion -eq "auto" -and $DownloadBinary -eq "local"){ #Take the version from the local binary only, requires only one version in that folder to work
    $name = (dir -Filter cef_binary_*_windows64.$Extension $CefBinaryDir)[0].Name;
    $CefVersion = ($name -replace "cef_binary_", "") -replace "_windows64.$Extension";
}


$Cef = Join-Path $WorkingDir 'cef'
$CefInclude = Join-Path $Cef 'include'
$Cef32 = Join-Path $WorkingDir 'cef_binary_3.y.z_windows32'
$Cef32vcx = Join-Path (Join-Path $Cef32 'libcef_dll_wrapper') 'libcef_dll_wrapper.vcxproj'
$Cef64 = Join-Path $WorkingDir  'cef_binary_3.y.z_windows64'
$Cef64vcx = Join-Path (Join-Path $Cef64 'libcef_dll_wrapper') 'libcef_dll_wrapper.vcxproj'

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

# Set CefVersion based on tag name - must start with leading "v" e.g. v3.3163.1663.g416ffeb
if ($env:APPVEYOR_REPO_TAG -eq "True")
{
    $CefVersion = "$env:APPVEYOR_REPO_TAG_NAME".Substring(1)  # trim leading "v"
    Write-Diagnostic "Setting version based on tag to $CefVersion"
}

# Take the cef version and strip the commit hash
$CefPackageVersion = $CefVersion.SubString(0, $CefVersion.LastIndexOf('.'))

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

   # NOTE: A better solution would be to use PSCX's Push-EnvironmentBlock before calling
   # this and popping it before calling this function again as repeated use of this function
   # can (unsurprisingly) cause the PATH variable to max out at Windows upper limit.
   $batFile = [IO.Path]::GetTempFileName() + '.cmd'
   Set-Content -Path $batFile -Value "`"$Path`" $Parameters && set > `"$tempFile`"`r`n"

   & $batFile

   Get-Content $tempFile | Foreach-Object {
       if ($_ -match "^(.*?)=(.*)$")
       {
           Set-Content "env:\$($matches[1])" $matches[2]
       }
   }
   Remove-Item $tempFile
   Remove-Item $batFile
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

    if ($Yes) {
        return $Value
    }

    $Value2

}

function Bootstrap
{
    param()

    if ($Target -eq "nupkg-only") {
        return
    }

    Write-Diagnostic "Bootstrapping"

    if (Test-Path($Cef)) {
        Remove-Item $Cef -Recurse | Out-Null
    }

    # Copy include files
    Copy-Item $Cef64\include $CefInclude -Recurse | Out-Null

    # Create default directory structure
    md 'cef\win32' | Out-Null
    md 'cef\win32\debug' | Out-Null
    md 'cef\win32\debug\VS2012' | Out-Null
    md 'cef\win32\debug\VS2013' | Out-Null
    md 'cef\win32\debug\VS2015' | Out-Null
    md 'cef\win32\debug\VS2017' | Out-Null
    md 'cef\win32\release' | Out-Null
    md 'cef\win32\release\VS2012' | Out-Null
    md 'cef\win32\release\VS2013' | Out-Null
    md 'cef\win32\release\VS2015' | Out-Null
    md 'cef\win32\release\VS2017' | Out-Null
    md 'cef\x64' | Out-Null
    md 'cef\x64\debug' | Out-Null
    md 'cef\x64\debug\VS2012' | Out-Null
    md 'cef\x64\debug\VS2013' | Out-Null
    md 'cef\x64\debug\VS2015' | Out-Null
    md 'cef\x64\debug\VS2017' | Out-Null
    md 'cef\x64\release' | Out-Null
    md 'cef\x64\release\VS2012' | Out-Null
    md 'cef\x64\release\VS2013' | Out-Null
    md 'cef\x64\release\VS2015' | Out-Null
    md 'cef\x64\release\VS2017' | Out-Null
}

function Msvs
{
    param(
        [ValidateSet('v110', 'v120', 'v140', 'v141')]
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

    $VisualStudioVersion = $null
    $VXXCommonTools = $null
    $CmakeGenerator = $null

    switch -Exact ($Toolchain) {
        'v110' {
            $VisualStudioVersion = '11.0'
            $VXXCommonTools = Join-Path $env:VS110COMNTOOLS '..\..\vc'
            $CmakeGenerator = 'Visual Studio 11'
        }
        'v120' {
            $VisualStudioVersion = '12.0'
            $VXXCommonTools = Join-Path $env:VS120COMNTOOLS '..\..\vc'
            $CmakeGenerator = 'Visual Studio 12'
        }
        'v140' {
            $VisualStudioVersion = '14.0'
            $VXXCommonTools = Join-Path $env:VS140COMNTOOLS '..\..\vc'
            $CmakeGenerator = 'Visual Studio 14'
        }
        'v141' {
            $programFilesDir = (${env:ProgramFiles(x86)}, ${env:ProgramFiles} -ne $null)[0]

            $vswherePath = Join-Path $programFilesDir 'Microsoft Visual Studio\Installer\vswhere.exe'
            #Check if we already have vswhere which is included in newer versions of VS2017
            if(-not (Test-Path $vswherePath))
            {
				Write-Diagnostic "Downloading VSWhere as no install found at $vswherePath"
				
                # Check if we already have a local copy and download if required
                $vswherePath = Join-Path $WorkingDir \vswhere.exe
                
                # TODO: Check hash and download if hash differs
                if(-not (Test-Path $vswherePath))
                {
                    $client = New-Object System.Net.WebClient;
                    $client.DownloadFile('https://github.com/Microsoft/vswhere/releases/download/2.2.11/vswhere.exe', $vswherePath);
                }
            }
			
			Write-Diagnostic "VSWhere path $vswherePath"
			
            $VS2017InstallPath = & $vswherePath -version 15 -property installationPath
			
			Write-Diagnostic "VS2017InstallPath: $VS2017InstallPath"
                
            if(-not (Test-Path $VS2017InstallPath))
			{
                Die "Visual Studio 2017 was not found"
            }
                
            $VisualStudioVersion = '15.0'
            $VXXCommonTools = Join-Path $VS2017InstallPath VC\Auxiliary\Build
            $CmakeGenerator = 'Visual Studio 15'
       }
    }

    if ($VXXCommonTools -eq $null -or (-not (Test-Path($VXXCommonTools)))) {
        Die 'Error unable to find any visual studio environment'
    }

    $CefProject = TernaryReturn ($Platform -eq 'x86') $Cef32vcx $Cef64vcx
    $CefDir = TernaryReturn ($Platform -eq 'x86') $Cef32 $Cef64

    $Arch = TernaryReturn ($Platform -eq 'x64') 'x64' 'win32'
    $CmakeArch = TernaryReturn ($Platform -eq 'x64') ' Win64' ''

    $VCVarsAll = Join-Path $VXXCommonTools vcvarsall.bat
    if (-not (Test-Path $VCVarsAll)) {
        Warn "Toolchain $Toolchain is not installed on your development machine, skipping $Configuration $Platform build."
        Return
    }

    $VCXProj = $Cef32vcx
    if ($Platform -eq 'x64') {
        $VCXProj = $Cef64vcx
    }

    # Only configure build environment once
    if ($env:CEFSHARP_BUILD_IS_BOOTSTRAPPED -ne "$Toolchain$Platform") {
        Invoke-BatchFile $VCVarsAll $Platform
        pushd $CefDir
        # Remove previously generated CMake data for the different platform/toolchain
        rm CMakeCache.txt -ErrorAction:SilentlyContinue
        rm -r CMakeFiles -ErrorAction:SilentlyContinue
        cmake -G "$CmakeGenerator$CmakeArch" -DUSE_SANDBOX=Off
        popd
        $env:CEFSHARP_BUILD_IS_BOOTSTRAPPED = "$Toolchain$Platform"
    }

    # Manually change project file to compile using /MDd and /MD
    (Get-Content $CefProject) | Foreach-Object {$_ -replace "<RuntimeLibrary>MultiThreadedDebug</RuntimeLibrary>", '<RuntimeLibrary>MultiThreadedDebugDLL</RuntimeLibrary>'} | Set-Content $CefProject
    (Get-Content $CefProject) | Foreach-Object {$_ -replace "<RuntimeLibrary>MultiThreaded</RuntimeLibrary>", '<RuntimeLibrary>MultiThreadedDLL</RuntimeLibrary>'} | Set-Content $CefProject

    $Arguments = @(
        "$CefProject",
        "/t:rebuild",
        "/p:VisualStudioVersion=$VisualStudioVersion",
        "/p:Configuration=$Configuration",
        "/p:PlatformToolset=$Toolchain",
        "/p:Platform=$Arch",
        "/p:PreferredToolArchitecture=$Arch",
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
	$StartInfo.RedirectStandardError = $true
	$StartInfo.RedirectStandardOutput = $true

    $Process = New-Object System.Diagnostics.Process
    $Process.StartInfo = $startInfo
    $Process.Start()
	
	$stdout = $Process.StandardOutput.ReadToEnd()
	$stderr = $Process.StandardError.ReadToEnd()
	
    $Process.WaitForExit()

    if ($Process.ExitCode -ne 0)
	{
		Write-Host "stdout: $stdout"
		Write-Host "stderr: $stderr"
        Die "Build failed"
    }

    CreateCefSdk $Toolchain $Configuration $Platform
}

function VSX
{
    param(
        [ValidateSet('v110', 'v120', 'v140', 'v141')]
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        [string] $Toolchain
    )

    Write-Diagnostic "Starting to build targeting toolchain $Toolchain"

    if (! $NoDebugBuild){
        Msvs "$Toolchain" 'Debug' 'x86'
    }
    Msvs "$Toolchain" 'Release' 'x86'
    if (! $NoDebugBuild){
        Msvs "$Toolchain" 'Debug' 'x64'
    }
    Msvs "$Toolchain" 'Release' 'x64'

    Write-Diagnostic "Finished build targeting toolchain $Toolchain"
}

function CreateCefSdk
{
    param(
        [ValidateSet('v110', 'v120', 'v140', 'v141')]
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
    if($Toolchain -eq "v141") {
        $VisualStudioVersion = "VS2017"
    } elseif($Toolchain -eq "v140") {
        $VisualStudioVersion = "VS2015"
    } elseif ($Toolchain -eq "v110") {
        $VisualStudioVersion = "VS2012"
    } else {
        $VisualStudioVersion = "VS2013"
    }

    $Arch = TernaryReturn ($Platform -eq 'x64') 'x64' 'win32'
    $CefArchDir = TernaryReturn ($Platform -eq 'x64') $Cef64 $Cef32

    # cef_binary_3.y.z_windows32\out\debug\lib -> cef\win32\debug\vs2013
    Copy-Item $CefArchDir\libcef_dll_wrapper\$Configuration\libcef_dll_wrapper.lib $Cef\$Arch\$Configuration\$VisualStudioVersion | Out-Null

    # cef_binary_3.y.z_windows32\debug -> cef\win32\debug
    Copy-Item $CefArchDir\$Configuration\libcef.lib $Cef\$Arch\$Configuration | Out-Null
}

function Nupkg
{
    Write-Diagnostic "Building nuget package"

    $Nuget = Join-Path $env:LOCALAPPDATA .\nuget\NuGet.exe
    if (-not (Test-Path $Nuget)) {
        Die "Please install nuget. More information available at: http://docs.nuget.org/docs/start-here/installing-nuget"
    }

    # Build 32bit packages
    . $Nuget pack nuget\cef.redist.nuspec -NoPackageAnalysis -Version $CefPackageVersion -Properties 'Configuration=Release;Platform=x86;CPlatform=windows32;' -OutputDirectory nuget

    # Build 64bit packages
    . $Nuget pack nuget\cef.redist.nuspec -NoPackageAnalysis -Version $CefPackageVersion -Properties 'Configuration=Release;Platform=x64;CPlatform=windows64;' -OutputDirectory nuget

    # Build sdk
    $Filename = Resolve-Path ".\nuget\cef.sdk.props"
    $Text = (Get-Content $Filename) -replace '<CefSdkVer>.*<\/CefSdkVer>', "<CefSdkVer>cef.sdk.$CefPackageVersion</CefSdkVer>"
    [System.IO.File]::WriteAllLines($Filename, $Text)

    . $Nuget pack nuget\cef.sdk.nuspec -NoPackageAnalysis -Version $CefPackageVersion -OutputDirectory nuget
	
	if ($env:APPVEYOR_REPO_TAG -eq "True")
    {
        appveyor PushArtifact "nuget\cef.redist.x86.$CefPackageVersion.nupkg"
		appveyor PushArtifact "nuget\cef.redist.x64.$CefPackageVersion.nupkg"
		appveyor PushArtifact "nuget\cef.sdk.$CefPackageVersion.nupkg"
    }
}

function DownloadNuget()
{
    $folder = Join-Path $env:LOCALAPPDATA .\nuget;
    $Nuget = Join-Path $folder .\NuGet.exe
    if (-not (Test-Path $Nuget))
    {
        mkdir $folder
        $Client = New-Object System.Net.WebClient;
        $Client.DownloadFile('http://nuget.org/nuget.exe', $Nuget);
    }
}

function DownloadCefBinaryAndUnzip()
{
    $Client = New-Object System.Net.WebClient;

    $CefBuildServerUrl = "http://opensource.spotify.com/cefbuilds/"
    $CefBuildServerJsonPackageList = $CefBuildServerUrl + "index.json"

    $CefBuildsJson = Invoke-WebRequest -Uri $CefBuildServerJsonPackageList | ConvertFrom-Json
    $CefWin32CefVersion = $CefBuildsJson.windows32.versions | Where-Object {$_.cef_version -eq $CefVersion}
    $CefWin64CefVersion = $CefBuildsJson.windows64.versions | Where-Object {$_.cef_version -eq $CefVersion}

    $Cef32FileName = ($CefWin32CefVersion.files | Where-Object {$_.type -eq "standard"}).name
    $Cef64FileName = ($CefWin64CefVersion.files | Where-Object {$_.type -eq "standard"}).name

    # Make sure there is a 32bit and 64bit version for the specified build
    if ($CefWin32CefVersion.cef_version -ne $CefWin64CefVersion.cef_version)
    {
        Die 'Win32 version is $CefWin32CefVersion.cef_version and Win64 version is $CefWin64CefVersion.cef_version - both must be the same'
    }

    set-alias sz "$env:ProgramFiles\7-Zip\7z.exe"

    $LocalFile = Join-Path $WorkingDir $Cef32FileName

    if (-not (Test-Path $LocalFile))
    {
        Write-Diagnostic "Downloading $Cef32FileName; this will take a while as the file is approximately 200 MiB large."
        $Client.DownloadFile($CefBuildServerUrl + $Cef32FileName, $LocalFile);
        Write-Diagnostic "Download $Cef32FileName complete"
  }

    if (-not (Test-Path (Join-Path $Cef32 '\include\cef_version.h')))
    {
        # Extract bzip file
        sz e $LocalFile

        # Extract tar file
        $TarFile = ($LocalFile).Substring(0, $LocalFile.length - 4)
        sz x $TarFile

        # Sleep for a short period to allow 7z to release it's file handles
        sleep -m 2000

        # Remove tar file
        Remove-Item $TarFile

        $Folder = Join-Path $WorkingDir ($Cef32FileName.Substring(0, $Cef32FileName.length - 8))
        Move-Item ($Folder + '\*') $Cef32 -force
        Remove-Item $Folder
    }

    $LocalFile = Join-Path $WorkingDir $Cef64FileName

    if (-not (Test-Path $LocalFile))
    {
        Write-Diagnostic "Downloading $Cef64FileName; this will take a while as the file is approximately 200 MiB large."
        $Client.DownloadFile($CefBuildServerUrl + $Cef64FileName, $LocalFile);
        Write-Diagnostic "Download $Cef64FileName complete"
    }

    if (-not (Test-Path (Join-Path $Cef64 '\include\cef_version.h')))
    {
        # Extract bzip file
        sz e $LocalFile

        # Extract tar file
        $TarFile = ($LocalFile).Substring(0, $LocalFile.length - 4)
        sz x $TarFile

        # Sleep for a short period to allow 7z to release it's file handles
        sleep -m 2000

        # Remove tar file
        Remove-Item $TarFile

        $Folder = Join-Path $WorkingDir ($Cef64FileName.Substring(0, $Cef64FileName.length - 8))
        Move-Item ($Folder + '\*') $Cef64 -force
        Remove-Item $Folder
    }
}

function CopyFromLocalCefBuild()
{
    # Example file names from cefsource build:
    # 32-bit: cef_binary_3.2924.1538.gbfdeccd_windows32.tar.bz2
    # 64-bit: cef_binary_3.2924.1538.gbfdeccd_windows64.tar.bz2

    Write-Host $CefVersion

    $Cef32FileName = "cef_binary_$($CefVersion)_windows32." + $Extension;
    $Cef64FileName = "cef_binary_$($CefVersion)_windows64." + $Extension;

    set-alias sz "$env:ProgramFiles\7-Zip\7z.exe"

    if ([System.IO.Path]::IsPathRooted($CefBinaryDir))
    {
        $CefBuildDir = $CefBinaryDir
    }
    else
    {
        $CefBuildDir = Join-Path $WorkingDir "$CefBinaryDir/"
    }

    $LocalFile = Join-Path $WorkingDir $Cef32FileName

    if (-not (Test-Path $LocalFile))
    {
        Write-Diagnostic "Copy $Cef32FileName (approx 200mb)"
        Copy-Item ($CefBuildDir+$Cef32FileName) $LocalFile
        Write-Diagnostic "Copy of $Cef32FileName complete"
    }

    if (-not (Test-Path (Join-Path $Cef32 '\include\cef_version.h')))
    {
        # Extract bzip file
        sz x $LocalFile;

        if ($Extension -eq "tar.bz2"){
            # Extract tar file
            $TarFile = ($LocalFile).Substring(0, $LocalFile.length - 4)
            sz x $TarFile

            # Sleep for a short period to allow 7z to release it's file handles
            sleep -m 2000

            # Remove tar file
            Remove-Item $TarFile
        }

        $Folder = Join-Path $WorkingDir ($Cef32FileName.Substring(0, $Cef32FileName.length - ($Extension.Length+1)))
        Move-Item ($Folder + '\*') $Cef32 -force
        Remove-Item $Folder
    }

    $LocalFile = Join-Path $WorkingDir $Cef64FileName

    if (-not (Test-Path $LocalFile))
    {
        Write-Diagnostic "Copy $Cef64FileName (approx 200mb)"
        Copy-Item ($CefBuildDir+$Cef64FileName) $LocalFile;
        Write-Diagnostic "Copy of $Cef64FileName complete"
    }

    if (-not (Test-Path (Join-Path $Cef64 '\include\cef_version.h')))
    {
        # Extract bzip file
        sz x $LocalFile;

        if ($Extension -eq "tar.bz2"){
            # Extract tar file
            $TarFile = ($LocalFile).Substring(0, $LocalFile.length - 4)
            sz x $TarFile

            # Sleep for a short period to allow 7z to release it's file handles
            sleep -m 2000

            # Remove tar file
            Remove-Item $TarFile
        }
        $Folder = Join-Path $WorkingDir ($Cef64FileName.Substring(0, $Cef64FileName.length - ($Extension.Length+1)))
        Move-Item ($Folder + '\*') $Cef64 -force
        Remove-Item $Folder
    }
}

function CheckDependencies()
{
    # Check for cmake
    if ((Get-Command "cmake.exe" -ErrorAction SilentlyContinue) -eq $null)
    {
        Die "Unable to find cmake.exe in your PATH"
    }

    # Check for 7zip
    if (-not (test-path "$env:ProgramFiles\7-Zip\7z.exe"))
    {
        Die "$env:ProgramFiles\7-Zip\7z.exe is required"
    }
}

CheckDependencies

switch -Exact ($DownloadBinary)
{
    "none" {
    }
    "download"
    {
        DownloadCefBinaryAndUnzip
    }
    "local"
    {
        CopyFromLocalCefBuild
    }
}

DownloadNuget

Bootstrap

switch -Exact ($Target) {
    "nupkg" {
        #VSX v110
        #VSX v120
        VSX v141
		VSX v140
        Nupkg
    }
    "nupkg-only" {
        Nupkg
    }
    "vs2013" {
        VSX v120
    }
    "vs2012" {
        VSX v110
    }
    "vs2015" {
        VSX v140
    }
    "vs2017" {
        VSX v141
    }
}
}catch{
    WriteException $_;
}