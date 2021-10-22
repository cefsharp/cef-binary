#requires -Version 5

param(
	[ValidateSet("vs2019", "vs2022", "nupkg", "nupkg-only")]
	[Parameter(Position = 0)]
	[string] $Target = "nupkg",

	[ValidateSet("none", "download", "local")]
	[Parameter(Position = 1)]
	[string] $DownloadBinary = "download",

	[Parameter(Position = 2)]
	# absolute or relative path to directory containing cef binaries archives (used if DownloadBinary = local)
	[string] $CefBinaryDir = "../cefsource/chromium/src/cef/binary_distrib/",

	[Parameter(Position = 3)]
	$CefVersion = "95.7.8+g69b7dc3+chromium-95.0.4638.17",

	[ValidateSet("tar.bz2","zip","7z")]
	[Parameter(Position = 4)]
	[string] $Extension = "tar.bz2",
	
	[Parameter(Position = 5)]
	[Switch] $NoDebugBuild,
	
	[Parameter(Position = 6)]
	[string] $Suffix,

	[Parameter(Position = 7)]
	[string] $BuildArches = "win-x86;win-x64;win-arm64"
)

Set-StrictMode -version latest
$ErrorActionPreference = "Stop";
$Extension = $Extension.ToLower();

Function WriteException($exp)
{
	write-host "Caught an exception:" -ForegroundColor Yellow -NoNewline;
	write-host " $($exp.Exception.Message)" -ForegroundColor Red;
	write-host "`tException Type: $($exp.Exception.GetType().FullName)";
	$stack = $exp.ScriptStackTrace;
	$stack = $stack.replace("`n","`n`t");
	write-host "`tStack Trace: $stack";
	throw $exp;
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

	#Brace must be on same line for foreach-object to work
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

function DownloadDependencies()
{
	$folder = Join-Path $env:LOCALAPPDATA .\nuget;
	$Nuget = Join-Path $folder .\NuGet.exe
	if (-not (Test-Path $Nuget))
	{
		if (-not (Test-Path $folder))
		{
			mkdir $folder
		}
			
		$Client = New-Object System.Net.WebClient;
		$Client.DownloadFile('https://dist.nuget.org/win-x86-commandline/v5.11.0/nuget.exe', $Nuget);
	}

	$global:VSWherePath = Join-Path ${env:ProgramFiles} 'Microsoft Visual Studio\Installer\vswhere.exe'

	if(-not (Test-Path $global:VSWherePath))
	{
		$global:VSWherePath = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
	}

	#Check if we already have vswhere which is included in newer versions of VS2019/VS2022
	if(-not (Test-Path $global:VSwherePath))
	{
		Write-Diagnostic "Downloading VSWhere as no install found at $global:VSwherePath"
		
		# Check if we already have a local copy and download if required
		$global:VSwherePath = Join-Path $WorkingDir \vswhere.exe
		
		# TODO: Check hash and download if hash differs
		if(-not (Test-Path $global:VSwherePath))
		{
			$client = New-Object System.Net.WebClient;
			$client.DownloadFile('https://github.com/Microsoft/vswhere/releases/download/2.5.2/vswhere.exe', $global:VSwherePath);
		}
	}
}

function WriteVersionToRuntimeJson
{
	$Filename = Join-Path $WorkingDir NuGet\chromiumembeddedframework.runtime.json
		
	Write-Diagnostic  "Write Version ($CefPackageVersion) to $Filename"
	$Regex1  = '": ".*"';
	$Replace = '": "' + $CefPackageVersion + '"';
		
	$RunTimeJsonData = Get-Content -Encoding UTF8 $Filename
	$NewString = $RunTimeJsonData -replace $Regex1, $Replace
		
	$Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
	[System.IO.File]::WriteAllLines($Filename, $NewString, $Utf8NoBomEncoding)
}

function CheckDependencies()
{
	# Check for cmake
	if ($null -eq (Get-Command "cmake.exe" -ErrorAction SilentlyContinue))
	{
		Die "Unable to find cmake.exe in your PATH"
	}

	# Check for 7zip
	if (-not (test-path "$env:ProgramFiles\7-Zip\7z.exe"))
	{
		Die "$env:ProgramFiles\7-Zip\7z.exe is required"
	}
}

function Bootstrap
{
	param(
		[Parameter(Position = 0, ValueFromPipeline = $true)]
		$Platform
	)

	Write-Diagnostic ("Creating folders for " + $Platform.ArchLong)

	# Create default directory structure
	$path = $Platform.Folder
	# Copy include files and license.txt
	Copy-Item $path\include $CefIncludeFolder -Recurse -Force | Out-Null
	Copy-Item $path\License.txt $CefWorkingFolder -Force | Out-Null

	$arch = $Platform.NativeArch

	mkdir "cef\$arch" | Out-Null
	mkdir "cef\$arch\debug" | Out-Null
	mkdir "cef\$arch\debug\VS2019" | Out-Null
	mkdir "cef\$arch\debug\VS2022" | Out-Null
	mkdir "cef\$arch\release" | Out-Null
	mkdir "cef\$arch\release\VS2019" | Out-Null
	mkdir "cef\$arch\release\VS2022" | Out-Null
}

function Msvs
{
	param(
		[ValidateSet('v142', 'v143')]
		[Parameter(Position = 0, ValueFromPipeline = $true)]
		[string] $Toolchain,

		[Parameter(Position = 1, ValueFromPipeline = $true)]
		[ValidateSet('Debug', 'Release')]
		[string] $Configuration,

		[Parameter(Position = 2, ValueFromPipeline = $true)]
		[hashtable] $Platform
	)

	Write-Diagnostic "Targeting $Toolchain using configuration $Configuration on platform ($Platform.ArchLong)"

	$VisualStudioVersion = $null
	$VXXCommonTools = $null
	$CmakeGenerator = $null
	$CefProject = [IO.Path]::Combine($Platform.Folder, 'libcef_dll_wrapper','libcef_dll_wrapper.vcxproj');
	$CefDir = $Platform.Folder
	$Arch = $Platform.NativeArch

	$VS_VER = 16;
	$VS_OFFICIAL_VER = 2019;
		
	if ($_ -eq 'v143')
	{
		$VS_VER=17;
		$VS_OFFICIAL_VER=2021;
	}
	
	Write-Diagnostic "VSWhere path $global:VSwherePath"

	$versionSearchStr = "[$VS_VER.0," + ($VS_VER+1) + ".0)"
	$VSInstallPath = & $global:VSwherePath -version $versionSearchStr -property installationPath
	
	Write-Diagnostic "$($VS_OFFICIAL_VER)InstallPath: $VSInstallPath"
		
	if($null -eq $VSInstallPath -or !(Test-Path $VSInstallPath))
	{
		Die "Visual Studio $VS_OFFICIAL_VER was not found"
	}
		
	$VisualStudioVersion = "$VS_VER.0"
	$VXXCommonTools = Join-Path $VSInstallPath VC\Auxiliary\Build
	$CmakeGenerator = "Visual Studio $VS_VER"

	if ($null -eq $VXXCommonTools -or (-not (Test-Path($VXXCommonTools))))
	{
		Die 'Error unable to find any visual studio environment'
	}

	$VCVarsAll = Join-Path $VXXCommonTools vcvarsall.bat
	if (-not (Test-Path $VCVarsAll))
	{
		Warn "Toolchain $Toolchain is not installed on your development machine, skipping $Configuration $Arch build."
		Return
	}

	$VCVarsAllArch = $Platform.Arch
	if ($VCVarsAllArch -eq "arm64")
	{
		$VCVarsAllArch = 'x64_arm64'
	}
		
	# Store the current environment variables so that we can reset them after running the build.
	# This is because vcvarsall.bat appends e.g. to the PATH variable every time it is called,
	# which can eventually lead to an error like "The input line is too long." when the PATH
	# gets too long.
	$PreviousEnvPath = $Env:Path
	$PreviousEnvLib = $Env:Lib
	$PreviousEnvLibPath = $Env:LibPath
	$PreviousEnvInclude = $Env:Include

	try
	{
		# Configure build environment
		Invoke-BatchFile $VCVarsAll $VCVarsAllArch
		Write-Diagnostic "pushd $CefDir"
		Push-Location $CefDir
		# Remove previously generated CMake data for the different platform/toolchain
		Remove-Item CMakeCache.txt -ErrorAction:SilentlyContinue
		Remove-Item -r CMakeFiles -ErrorAction:SilentlyContinue
		$cmake_path = "cmake.exe";
		if ($env:ChocolateyInstall -And (Test-Path ($env:ChocolateyInstall + "\bin\" + $cmake_path)))
		{
			$cmake_path = $env:ChocolateyInstall + "\bin\" + $cmake_path;           
		}
		&"$cmake_path" --version
		Write-Diagnostic "Running cmake: $cmake_path  -Wno-dev -LAH -G '$CmakeGenerator' -A $Arch -DUSE_SANDBOX=Off -DCEF_RUNTIME_LIBRARY_FLAG=/MD ."
		&"$cmake_path"  -Wno-dev -LAH -G "$CmakeGenerator" -A $Arch -DUSE_SANDBOX=Off -DCEF_RUNTIME_LIBRARY_FLAG=/MD .
		Pop-Location

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

		#Brace must be on same line for foreach-object to work
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
			Write-Host "Ran msbuild.exe with args: $Arguments"
			Write-Host "stdout: $stdout"
			Write-Host "stderr: $stderr"
			Die "Build failed"
		}

		CreateCefSdk $Toolchain $Configuration $Platform
	}
	finally
	{
		# Reset the environment variables to their previous values.        
		$Env:Path = $PreviousEnvPath
		$Env:Lib = $PreviousEnvLib
		$Env:LibPath = $PreviousEnvLibPath
		$Env:Include = $PreviousEnvInclude
	}
}

function VSX
{
	param(
		[ValidateSet('v142', 'v143')]
		[Parameter(Position = 0, ValueFromPipeline = $true)]
		[string] $toolchain,

		[Parameter(Position = 1, ValueFromPipeline = $true)]
		[hashtable] $Platform
	)

	Write-Diagnostic "Starting to build targeting toolchain $Toolchain"

	if (! $NoDebugBuild)
	{
		Msvs "$toolchain" 'Debug' $Platform
	}
	Msvs "$toolchain" 'Release' $Platform

	Write-Diagnostic "Finished build targeting toolchain $toolchain"
}

function CreateCefSdk
{
	param(
		[ValidateSet('v142', 'v143')]
		[Parameter(Position = 0, ValueFromPipeline = $true)]
		[string] $Toolchain,

		[Parameter(Position = 1, ValueFromPipeline = $true)]
		[ValidateSet('Debug', 'Release')]
		[string] $Configuration,

		[Parameter(Position = 2, ValueFromPipeline = $true)]
		[hashtable] $Platform
	)

	Write-Diagnostic "Creating sdk for $Toolchain"

	$VisualStudioVersion = "VS2019"
		
	if($Toolchain -eq "v143")
	{
		$VisualStudioVersion = "VS2022"
	}

	$CefArchDir = $Platform.Folder
	$Arch = $Platform.NativeArch;

	# cef_binary_3.y.z_windows32\out\debug\lib -> cef\win32\debug\vs2019
	Copy-Item $CefArchDir\libcef_dll_wrapper\$Configuration\libcef_dll_wrapper.lib $CefWorkingFolder\$Arch\$Configuration\$VisualStudioVersion | Out-Null
	Copy-Item $CefArchDir\libcef_dll_wrapper\$Configuration\libcef_dll_wrapper.pdb $CefWorkingFolder\$Arch\$Configuration\$VisualStudioVersion | Out-Null

	# cef_binary_3.y.z_windows32\debug -> cef\win32\debug
	Copy-Item $CefArchDir\$Configuration\libcef.lib $CefWorkingFolder\$Arch\$Configuration | Out-Null
}

function Nupkg
{
	Write-Diagnostic "Building nuget package"

	$Nuget = Join-Path $env:LOCALAPPDATA .\nuget\NuGet.exe
	if (-not (Test-Path $Nuget))
	{
		Die "Please install nuget. More information available at: http://docs.nuget.org/docs/start-here/installing-nuget"
	}

	foreach ($platform in $Platforms.Values)
	{
		if(!$platform.Enabled)
		{
			continue
		}

		$arch = $platform.Arch
		$archLong = $platform.ArchLong

		# Build packages
		if ($arch -ne "arm64")
		{
			. $Nuget pack nuget\cef.redist.nuspec -NoPackageAnalysis -Version $CefPackageVersion -Properties "Configuration=Release;Platform=$arch;CPlatform=$archLong;" -OutputDirectory nuget
		}

		. $Nuget pack nuget\chromiumembeddedframework.runtime.win.nuspec -NoPackageAnalysis -Version $CefPackageVersion -Properties "Configuration=Release;Platform=$arch;CPlatform=$archLong;" -OutputDirectory nuget
	}
		
	# Meta Package
	. $Nuget pack nuget\chromiumembeddedframework.runtime.nuspec -NoPackageAnalysis -Version $CefPackageVersion -Properties 'Configuration=Release;' -OutputDirectory nuget

	# Build sdk
	$Filename = Resolve-Path ".\nuget\cef.sdk.props"
	$Text = (Get-Content $Filename) -replace '<CefSdkVer>.*<\/CefSdkVer>', "<CefSdkVer>cef.sdk.$CefPackageVersion</CefSdkVer>"
	[System.IO.File]::WriteAllLines($Filename, $Text)

	. $Nuget pack nuget\cef.sdk.nuspec -NoPackageAnalysis -Version $CefPackageVersion -OutputDirectory nuget
	
	if ($env:APPVEYOR_REPO_TAG -eq "True")
	{
		Get-ChildItem -Path .\Nuget -Filter *.nupkg -File | ForEach-Object {
			appveyor PushArtifact $_.FullName
		} | Out-Null
	}
}

function ExtractArchive()
{
	param(
		[Parameter(Position = 0, ValueFromPipeline = $true)]
		[string] $ArchivePath,
		[Parameter(Position = 1, ValueFromPipeline = $true)]
		[string] $CefFileName,
		[Parameter(Position = 2, ValueFromPipeline = $true)]
		[string] $OutputFolder
	)

	set-alias sz "$env:ProgramFiles\7-Zip\7z.exe"

	# Extract bzip file
	sz x $ArchivePath;

	if ($Extension -eq "tar.bz2")
	{
		# Extract tar file
		$TarFile = ($ArchivePath).Substring(0, $ArchivePath.length - 4)
		sz x $TarFile

		# Sleep for a short period to allow 7z to release it's file handles
		Start-Sleep -m 2000

		# Remove tar file
		Remove-Item $TarFile
	}

	$Folder = Join-Path $WorkingDir ($CefFileName.Substring(0, $CefFileName.length - ($Extension.Length+1)))
	Move-Item ($Folder + '\*') $OutputFolder -force
	Remove-Item $Folder
}

function DownloadCefBinaryAndUnzip()
{
	param(
		[Parameter(Position = 0, ValueFromPipeline = $true)]
		[hashtable] $Platform
	)

	$CefBuildServerUrl = "https://cef-builds.spotifycdn.com/"

	if($null -eq $global:CefBuildsJson)
	{
		$CefBuildServerJsonPackageList = $CefBuildServerUrl + "index.json"

		$global:CefBuildsJson = Invoke-WebRequest -UseBasicParsing -Uri $CefBuildServerJsonPackageList | ConvertFrom-Json
	}
	
	$arch = $Platform.ArchLong

	$CefWinCefVersion = $global:CefBuildsJson.($arch).versions | Where-Object {$_.cef_version -eq $CefVersion}

	if($null -eq $CefWinCefVersion)
	{
		Die "Build Unavailable - $arch has no files for version $CefVersion"
	}

	#TODO Duplication
	$CefFileName = ($CefWinCefVersion.files | Where-Object {$_.type -eq "standard"}).name
	$CefFileHash = ($CefWinCefVersion.files | Where-Object {$_.type -eq "standard"}).sha1
	$CefFileSize = (($CefWinCefVersion.files | Where-Object {$_.type -eq "standard"}).size /1MB)

	$LocalFile = Join-Path $WorkingDir $CefFileName
	if (-not (Test-Path $LocalFile))
	{
		$Client = New-Object System.Net.WebClient;

		Write-Diagnostic "Downloading $CefFileName; this will take a while as the file is $CefFileSize MB."
		$Client.DownloadFile($CefBuildServerUrl + [System.Web.HttpUtility]::UrlEncode($CefFileName), $LocalFile);

		if (-not (Test-Path $LocalFile))
		{
			Die "Downloading $CefFileName failed"
		}
				
		$CefLocalFileHash = (Get-FileHash -Path $LocalFile -Algorithm SHA1).Hash
				
		Write-Diagnostic "Download $CefFileName complete"
		Write-Diagnostic "Expected SHA1 for $CefFileName $CefFileHash"
		Write-Diagnostic "Actual SHA1 for $CefFileName $CefLocalFileHash"
							
		if($CefLocalFileHash -ne $CefFileHash)
		{
			Die "SHA1 hash did not match"
		}
	}

	if (-not (Test-Path (Join-Path $Platform.Folder '\include\cef_version.h')))
	{
		ExtractArchive $LocalFile $CefFileName $Platform.Folder
	}
}

function CopyFromLocalCefBuild()
{
	param(
		[Parameter(Position = 0, ValueFromPipeline = $true)]
		[hashtable] $Platform
	)

	# Example file names from cefsource build:
	# 32-bit: cef_binary_3.2924.1538.gbfdeccd_windows32.tar.bz2
	# 64-bit: cef_binary_3.2924.1538.gbfdeccd_windows64.tar.bz2

	$archLong = $Platform.ArchLong

	$CefFileName = "cef_binary_$($CefVersion)_$archLong." + $Extension;

	$LocalFile = Join-Path $WorkingDir $CefFileName

	if (-not (Test-Path $LocalFile))
	{
		Write-Diagnostic "Copy $CefFileName (approx 200mb)"
		Copy-Item ($CefBinaryDir+$CefFileName) $LocalFile
		Write-Diagnostic "Copy of $CefFileName complete"
	}

	if (-not (Test-Path (Join-Path $Platform.Folder '\include\cef_version.h')))
	{
		ExtractArchive $LocalFile $CefFileName $Platform.Folder
	}
}

try
{
	$global:CefBuildsJson = $null
	$VSwherePath = $null
	$WorkingDir = split-path -parent $MyInvocation.MyCommand.Definition;

	Write-Diagnostic "pushd $WorkingDir"
	Push-Location $WorkingDir

	$CefWorkingFolder = Join-Path $WorkingDir 'cef'
	$CefIncludeFolder = Join-Path $CefWorkingFolder 'include'

	$Platforms = @{
		'win-x86'=@{
			Enabled=($BuildArches.Contains('win-x86') -or $BuildArches.Contains('x86'));
			NativeArch='win32';
			Arch='x86';
			ArchLong='windows32';
			Folder=Join-Path $WorkingDir 'cef_binary_3.y.z_windows32';
		};
		
		'win-x64'=@{
			Enabled=$BuildArches.Contains('win-x64') -or $BuildArches.Contains('x64');
			NativeArch='x64';
			Arch='x64';
			ArchLong='windows64';
			Folder=Join-Path $WorkingDir 'cef_binary_3.y.z_windows64';
		};
		
		'win-arm64'=@{
			Enabled=($BuildArches.Contains('win-arm64') -or $BuildArches.Contains('arm64'));
			NativeArch='arm64';
			Arch='arm64';
			ArchLong='windowsarm64';
			Folder=Join-Path $WorkingDir 'cef_binary_3.y.z_windowsarm64';
		};
	}

	if($DownloadBinary -eq "local")
	{
		if ([System.IO.Path]::IsPathRooted($CefBinaryDir))
		{
			$CefBinaryDir = $CefBinaryDir
		}
		else
		{
			$CefBinaryDir = [System.IO.Path]::GetFullPath((Join-Path $WorkingDir "$CefBinaryDir/"))
		}
		
		if ($CefVersion -eq "auto")
		{
			$enabledPlatform = $Platforms.GetEnumerator() | Where-Object {
				$_.Value.Enabled -eq $true
			}

			$enabledPlatformFileExtension =  $enabledPlatform[0].Value.ArchLong + '.' + $Extension
			
			#Take the version from the local binary only
			$name = (Get-ChildItem -Filter cef_binary_*_$enabledPlatformFileExtension $CefBinaryDir)[0].Name;
			$CefVersion = ($name -replace "cef_binary_", "") -replace "_$enabledPlatformFileExtension";
		}
	}

	# Set CefVersion based on tag name - must start with leading "v" e.g. v3.3163.1663.g416ffeb
	if ($env:APPVEYOR_REPO_TAG -eq "True")
	{
		$CefVersion = "$env:APPVEYOR_REPO_TAG_NAME".Substring(1)  # trim leading "v"
		Write-Diagnostic "Setting version based on tag to $CefVersion"
	}
	
	# Take the cef version and strip the commit hash, chromium version 
	# we should end up with something like 73.1.12
	$CefPackageVersion = $CefVersion.SubString(0, $CefVersion.IndexOf('+'))
	
	if($Suffix)
	{
		$CefPackageVersion = $CefPackageVersion + '-' + $Suffix
	}

	CheckDependencies
	DownloadDependencies
	WriteVersionToRuntimeJson

	Write-Diagnostic("CEF Version: $CefVersion")
	Write-Diagnostic("Enabled Architectures")

	foreach($platform in $Platforms.Values)
	{
		if($platform.Enabled)
		{
			Write-Diagnostic("Arch: " + $platform.ArchLong)
		}
	}

	if($Target -eq "nupkg-only")
	{
		Nupkg
		return;
	}

	Write-Diagnostic ("Deleting working folder $CefWorkingFolder")

	if (Test-Path($CefWorkingFolder))
	{
		Remove-Item $CefWorkingFolder -Recurse | Out-Null
	}

	foreach ($platform in $Platforms.Values)
	{
		if(!$platform.Enabled)
		{
			continue
		}

		switch -Exact ($DownloadBinary)
		{
			"none"
			{
			}
			"download"
			{
				DownloadCefBinaryAndUnzip $platform
			}
			"local"
			{
				CopyFromLocalCefBuild $platform
			}
		}

		Bootstrap $platform
	}

	# Loop through twice so the files have been downloaded
	# extracted and validated before we attempt to build
	# makes sure we have all platforms
	foreach ($platform in $Platforms.Values)
	{
		# Create the folders for any that don't exist so the nuget packages are created with empty folders
		# This can be removed once the new chromiumembeddedframework.runtime.resource package is created
		[System.IO.Directory]::CreateDirectory([IO.Path]::Combine($platform.Folder, 'Resources','locales'))
		[System.IO.Directory]::CreateDirectory([IO.Path]::Combine($platform.Folder, 'Release','swiftshader'))

		if(!$platform.Enabled)
		{
			continue
		}

		switch -Exact ($Target)
		{
			"nupkg"
			{
				VSX v142 $platform
			}
			"vs2022"
			{
				VSX v143 $platform
			}
			"vs2019"
			{
				VSX v142 $platform
			}
		}
	}

	if($Target -eq "nupkg")
	{
		Nupkg
	}
}
catch
{
	WriteException $_;
}
finally
{
	Pop-Location
}
