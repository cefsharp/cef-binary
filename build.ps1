#requires -Version 5

param(
	[ValidateSet("vs2019", "vs2021", "nupkg", "nupkg-only")]
	[Parameter(Position = 0)]
	[string] $Target = "nupkg",

	[ValidateSet("none", "download", "local")]
	[Parameter(Position = 1)]
	[string] $DownloadBinary = "download",

	[Parameter(Position = 2)]
	# absolute or relative path to directory containing cef binaries archives (used if DownloadBinary = local)
	[string] $CefBinaryDir = "../cefsource/chromium/src/cef/binary_distrib/",

	[Parameter(Position = 3)]
	$CefVersion = "94.0.5+g506b164+chromium-94.0.4606.41",

	[ValidateSet("tar.bz2","zip","7z")]
	[Parameter(Position = 4)]
	[string] $Extension = "tar.bz2",
	
	[Parameter(Position = 5)]
	[Switch] $NoDebugBuild,
	
	[Parameter(Position = 6)]
	[string] $Suffix,

	[Parameter(Position = 7)]
	[string] $BuildArches = "x86 x64 amd64"
)
$ARCHES = $BuildArches.Split(" ");
$ARCHES_TO_BITKEY = @{};
foreach ($arch in $ARCHES) {
	$arch_bit = $arch;
	if ($arch_bit.StartsWith("x")) {
		$arch_bit = $arch.Substring(1);
		if ($arch_bit -eq "86"){
			$arch_bit = "32";
		}
		$ARCHES_TO_BITKEY[$arch] = $arch_bit;
	}
}

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

try
{
	$WorkingDir = split-path -parent $MyInvocation.MyCommand.Definition;
	if ($CefVersion -eq "auto" -and $DownloadBinary -eq "local")
	{
		#Take the version from the local binary only, requires only one version in that folder to work

		$name = (dir -Filter cef_binary_*_windows$($ARCHES_TO_BITKEY[$ARCHES[0]]).$Extension $CefBinaryDir)[0].Name;
		$CefVersion = ($name -replace "cef_binary_", "") -replace "_windows$($ARCHES_TO_BITKEY[$ARCHES[0]]).$Extension";
	}
	$Cef = @{}
	$Cefvcx  = @{}

	$Cef[""] = Join-Path $WorkingDir 'cef'
	$CefInclude = Join-Path $Cef[""] 'include'

	foreach ($arch in $ARCHES) {
		$Cef[$arch] = Join-Path $WorkingDir "cef_binary_3.y.z_windows$($ARCHES_TO_BITKEY[$arch])";
		$Cefvcx[$arch] = Join-Path (Join-Path $Cef[$arch] 'libcef_dll_wrapper') 'libcef_dll_wrapper.vcxproj'
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

	# Set CefVersion based on tag name - must start with leading "v" e.g. v3.3163.1663.g416ffeb
	if ($env:APPVEYOR_REPO_TAG -eq "True")
	{
		$CefVersion = "$env:APPVEYOR_REPO_TAG_NAME".Substring(1)  # trim leading "v"
		Write-Diagnostic "Setting version based on tag to $CefVersion"
	}
	
	if($CefVersion.StartsWith('3.'))
	{
		# Take the cef version and strip the commit hash
		$CefPackageVersion = $CefVersion.SubString(0, $CefVersion.LastIndexOf('.'))
	}
	else
	{
		# Take the cef version and strip the commit hash, chromium version 
		# we should end up with something like 73.1.12
		$CefPackageVersion = $CefVersion.SubString(0, $CefVersion.IndexOf('+'))
	}
	
	if($Suffix)
	{
		$CefPackageVersion = $CefPackageVersion + '-' + $Suffix
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

		if ($Yes)
		{
			return $Value
		}

		$Value2

	}

	function Bootstrap
	{
		param()

		if ($Target -eq "nupkg-only")
		{
			return
		}

		Write-Diagnostic "Bootstrapping"

		if (Test-Path($Cef[""]))
		{
			Remove-Item $Cef[""] -Recurse | Out-Null
		}

		# Copy include files
		Copy-Item "$($Cef[$ARCHES[0]])\include" $CefInclude -Recurse | Out-Null

		# Create default directory structure
		foreach ($arch in $ARCHES) {
			if ($arch -eq "x86"){
				$arch = "win32";
			}
			md "cef\$arch" | Out-Null
			md "cef\$arch\debug" | Out-Null
			md "cef\$arch\debug\VS2019" | Out-Null
			md "cef\$arch\debug\VS2021" | Out-Null
			md "cef\$arch\release" | Out-Null
			md "cef\$arch\release\VS2019" | Out-Null
			md "cef\$arch\release\VS2021" | Out-Null
		}
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
			[ValidateSet('x86', 'x64', 'arm64')]
			[string] $Platform
		)

		Write-Diagnostic "Targeting $Toolchain using configuration $Configuration on platform $Platform"

		$VisualStudioVersion = $null
		$VXXCommonTools = $null
		$CmakeGenerator = $null

		$VS_VER = 16;
		$VS_OFFICIAL_VER = 2019;
		
		if ($_ -eq 'v143')
		{
			$VS_VER=17;
			$VS_OFFICIAL_VER=2021;
		}
		
		$programFilesDir = (${env:ProgramFiles(x86)}, ${env:ProgramFiles} -ne $null)[0]

		$vswherePath = Join-Path $programFilesDir 'Microsoft Visual Studio\Installer\vswhere.exe'
		#Check if we already have vswhere which is included in newer versions of VS2019/VS2021
		if(-not (Test-Path $vswherePath))
		{
			Write-Diagnostic "Downloading VSWhere as no install found at $vswherePath"
		
			# Check if we already have a local copy and download if required
			$vswherePath = Join-Path $WorkingDir \vswhere.exe
		
			# TODO: Check hash and download if hash differs
			if(-not (Test-Path $vswherePath))
			{
				$client = New-Object System.Net.WebClient;
				$client.DownloadFile('https://github.com/Microsoft/vswhere/releases/download/2.5.2/vswhere.exe', $vswherePath);
			}
		}
	
		Write-Diagnostic "VSWhere path $vswherePath"

		$versionSearchStr = "[$VS_VER.0," + ($VS_VER+1) + ".0)"
		$VSInstallPath = & $vswherePath -version $versionSearchStr -property installationPath
	
		Write-Diagnostic "$($VS_OFFICIAL_VER)InstallPath: $VSInstallPath"
		
		if($VSInstallPath -eq $null -or !(Test-Path $VSInstallPath))
		{
			Die "Visual Studio $VS_OFFICIAL_VER was not found"
		}
		
		$VisualStudioVersion = "$VS_VER.0"
		$VXXCommonTools = Join-Path $VSInstallPath VC\Auxiliary\Build
		$CmakeGenerator = "Visual Studio $VS_VER"

		if ($VXXCommonTools -eq $null -or (-not (Test-Path($VXXCommonTools))))
		{
			Die 'Error unable to find any visual studio environment'
		}

		$CefProject = $Cefvcx[$Platform]
		$CefDir = $Cef[$Platform]
		$Arch = $Platform
		if ($Arch -eq 'x86')
		{
			$Arch = "win32";
		}

		$VCVarsAll = Join-Path $VXXCommonTools vcvarsall.bat
		if (-not (Test-Path $VCVarsAll))
		{
			Warn "Toolchain $Toolchain is not installed on your development machine, skipping $Configuration $Platform build."
			Return
		}

		$VCXProj = $Cefvcx[$Platform]
		$VCVarsAllArch = $Platform
		if ($VCVarsAllArch -eq "arm64"){
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
			pushd $CefDir
			# Remove previously generated CMake data for the different platform/toolchain
			rm CMakeCache.txt -ErrorAction:SilentlyContinue
			rm -r CMakeFiles -ErrorAction:SilentlyContinue
			$cmake_path = "cmake.exe";
			if ($env:ChocolateyInstall -And (Test-Path ($env:ChocolateyInstall + "\bin\" + $cmake_path)))
			{
				$cmake_path = $env:ChocolateyInstall + "\bin\" + $cmake_path;           
			}
			&"$cmake_path" --version
			Write-Diagnostic "Running cmake: $cmake_path  -Wno-dev -LAH -G '$CmakeGenerator' -A $Arch -DUSE_SANDBOX=Off -DCEF_RUNTIME_LIBRARY_FLAG=/MD ."
			&"$cmake_path"  -Wno-dev -LAH -G "$CmakeGenerator" -A $Arch -DUSE_SANDBOX=Off -DCEF_RUNTIME_LIBRARY_FLAG=/MD .
			popd

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
			[string] $Toolchain
		)

		Write-Diagnostic "Starting to build targeting toolchain $Toolchain"

		foreach ($arch in $ARCHES) {

			if (! $NoDebugBuild)
			{
				Msvs "$Toolchain" 'Debug' "$arch"
			}
			Msvs "$Toolchain" 'Release' "$arch"
		}

		Write-Diagnostic "Finished build targeting toolchain $Toolchain"
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
			[ValidateSet('x86', 'x64', 'arm64')]
			[string] $Platform
		)

		Write-Diagnostic "Creating sdk for $Toolchain"

		$VisualStudioVersion = "VS2019"
		
		if($Toolchain -eq "v143")
		{
			$VisualStudioVersion = "VS2021"
		}

		$CefDir = $Cef[$Platform]
		$Arch = $Platform
		if ($Arch -eq 'x86')
		{
			$Arch = "win32";
		}

		# cef_binary_3.y.z_windows32\out\debug\lib -> cef\win32\debug\vs2019
		Copy-Item $CefDir\libcef_dll_wrapper\$Configuration\libcef_dll_wrapper.lib "$($Cef[''])\$Arch\$Configuration\$VisualStudioVersion" | Out-Null
		Copy-Item $CefDir\libcef_dll_wrapper\$Configuration\libcef_dll_wrapper.pdb "$($Cef[''])\$Arch\$Configuration\$VisualStudioVersion" | Out-Null

		# cef_binary_3.y.z_windows32\debug -> cef\win32\debug
		Copy-Item $CefDir\$Configuration\libcef.lib "$($Cef[''])\$Arch\$Configuration" | Out-Null
	}

	function Nupkg
	{
		Write-Diagnostic "Building nuget package"

		$Nuget = Join-Path $env:LOCALAPPDATA .\nuget\NuGet.exe
		if (-not (Test-Path $Nuget))
		{
			Die "Please install nuget. More information available at: http://docs.nuget.org/docs/start-here/installing-nuget"
		}
		$meta_template = "";
		foreach ($arch in $ARCHES) {
			# Build packages
			if ($arch -ne "arm64"){
				. $Nuget pack nuget\cef.redist.nuspec -NoPackageAnalysis -Version $CefPackageVersion -Properties "Configuration=Release;Platform=$arch;CPlatform=windows$($ARCHES_TO_BITKEY[$arch]);" -OutputDirectory nuget
			}
			. $Nuget pack nuget\chromiumembeddedframework.runtime.win.nuspec -NoPackageAnalysis -Version $CefPackageVersion -Properties "Configuration=Release;Platform=$arch;CPlatform=windows$($ARCHES_TO_BITKEY[$arch]);" -OutputDirectory nuget
			$meta_template += "<file src='..\cef_binary_3.y.z_windows$($ARCHES_TO_BITKEY[$arch])\Resources\locales\*.pak' target='CEF\win-$arch\locales'/>`n    <file src='..\cef_binary_3.y.z_windows$($ARCHES_TO_BITKEY[$arch])\`$Configuration`$\swiftshader\*.dll' target='CEF\win-$arch\swiftshader' />`n";
		}
		
		$meta_template += "<file src='..\cef_binary_3.y.z_windows$($ARCHES_TO_BITKEY[$ARCHES[0]])\LICENSE.txt' target='LICENSE.txt' />";
		$meta_spec_file = "nuget\chromiumembeddedframework.runtime.nuspec";
		$content = Get-Content "$($meta_spec_file).template";
		$content = $content -replace "META_REPLACE_DATA", $meta_template;
		$content | Out-File -FilePath $meta_spec_file;

		# Meta Package
		. $Nuget pack nuget\chromiumembeddedframework.runtime.nuspec -NoPackageAnalysis -Version $CefPackageVersion -Properties 'Configuration=Release;' -OutputDirectory nuget

		# Build sdk
		$Filename = Resolve-Path ".\nuget\cef.sdk.props"
		$Text = (Get-Content $Filename) -replace '<CefSdkVer>.*<\/CefSdkVer>', "<CefSdkVer>cef.sdk.$CefPackageVersion</CefSdkVer>"
		[System.IO.File]::WriteAllLines($Filename, $Text)

		. $Nuget pack nuget\cef.sdk.nuspec -NoPackageAnalysis -Version $CefPackageVersion -OutputDirectory nuget
	
		if ($env:APPVEYOR_REPO_TAG -eq "True")
		{
			foreach ($arch in $ARCHES) {
				if ($arch -ne "arm64"){
					appveyor PushArtifact "nuget\cef.redist.$($arch).$CefPackageVersion.nupkg"
				}
				appveyor PushArtifact "nuget\chromiumembeddedframework.runtime.win-$($arch).$CefPackageVersion.nupkg"
			}

			appveyor PushArtifact "nuget\chromiumembeddedframework.runtime.$CefPackageVersion.nupkg"
			appveyor PushArtifact "nuget\cef.sdk.$CefPackageVersion.nupkg"
		}
	}

	function DownloadNuget()
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
	}

	function DownloadCefBinaryAndUnzip()
	{
		$Client = New-Object System.Net.WebClient;

		$CefBuildServerUrl = "https://cef-builds.spotifycdn.com/"
		$CefBuildServerJsonPackageList = $CefBuildServerUrl + "index.json"

		$CefBuildsJson = Invoke-WebRequest -UseBasicParsing -Uri $CefBuildServerJsonPackageList | ConvertFrom-Json
		$cef_version_comp = $false


		set-alias sz "$env:ProgramFiles\7-Zip\7z.exe"
		foreach ($arch in $ARCHES) {
			$CefWinCefVersion = $CefBuildsJson["windows$ARCHES_TO_BITKEY[$arch]"].versions | Where-Object {$_.cef_version -eq $CefVersion}
			if (! $cef_version_comp){
				$cef_version_comp = $CefWinCefVersion.cef_version;
			}
			if ($cef_version_comp -ne $CefWinCefVersion.cef_version){
				Die "All versions of CEF must be the same but $arch is: $($CefWinCefVersion.cef_version) vs previous arch's of: $cef_version_comp";
			}

			$CefFileName = ($CefWinCefVersion.files | Where-Object {$_.type -eq "standard"}).name
			$CefFileHash = ($CefWinCefVersion.files | Where-Object {$_.type -eq "standard"}).sha1
			$CefFileSize = (($CefWinCefVersion.files | Where-Object {$_.type -eq "standard"}).size /1MB)

			$LocalFile = Join-Path $WorkingDir $CefFileName
			if (-not (Test-Path $LocalFile))
			{
				Write-Diagnostic "Downloading $CefFileName; this will take a while as the file is $CefFileSize MB."
				$Client.DownloadFile($CefBuildServerUrl + [System.Web.HttpUtility]::UrlEncode($CefFileName), $LocalFile);
				
				$CefLocalFileHash = (Get-FileHash -Path $LocalFile -Algorithm SHA1).Hash
				
				Write-Diagnostic "Download $CefFileName complete"
				Write-Diagnostic "Expected SHA1 for $CefFileName $CefFileHash"
				Write-Diagnostic "Actual SHA1 for $CefFileName $CefLocalFileHash"
							
				if($CefLocalFileHash -ne $CefFileHash)
				{
					Die "SHA1 hash did not match"
				}
			}

			if (-not (Test-Path (Join-Path $Cef[""] '\include\cef_version.h')))
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

				$Folder = Join-Path $WorkingDir ($CefFileName.Substring(0, $CefFileName.length - 8))
				Move-Item ($Folder + '\*') $Cef[$arch] -force
				Remove-Item $Folder
			}
		}

	}

	function CopyFromLocalCefBuild()
	{
		# Example file names from cefsource build:
		# 32-bit: cef_binary_3.2924.1538.gbfdeccd_windows32.tar.bz2
		# 64-bit: cef_binary_3.2924.1538.gbfdeccd_windows64.tar.bz2

		Write-Host $CefVersion

		foreach ($arch in $ARCHES) {
			$CefFileName = "cef_binary_$($CefVersion)_windows$($ARCHES_TO_BITKEY[$arch])." + $Extension;
			set-alias sz "$env:ProgramFiles\7-Zip\7z.exe"
			if ([System.IO.Path]::IsPathRooted($CefBinaryDir))
			{
				$CefBuildDir = $CefBinaryDir
			}
			else
			{
				$CefBuildDir = Join-Path $WorkingDir "$CefBinaryDir/"
			}

			$LocalFile = Join-Path $WorkingDir $CefFileName

			if (-not (Test-Path $LocalFile))
			{
				Write-Diagnostic "Copy $CefFileName (approx 200mb)"
				Copy-Item ($CefBuildDir+$CefFileName) $LocalFile
				Write-Diagnostic "Copy of $CefFileName complete"
			}

			if (-not (Test-Path (Join-Path $Cef[$arch] '\include\cef_version.h')))
			{
				# Extract bzip file
				sz x $LocalFile;

				if ($Extension -eq "tar.bz2")
				{
					# Extract tar file
					$TarFile = ($LocalFile).Substring(0, $LocalFile.length - 4)
					sz x $TarFile

					# Sleep for a short period to allow 7z to release it's file handles
					sleep -m 2000

					# Remove tar file
					Remove-Item $TarFile
				}

				$Folder = Join-Path $WorkingDir ($CefFileName.Substring(0, $CefFileName.length - ($Extension.Length+1)))
				Move-Item ($Folder + '\*') $Cef[$arch] -force
				Remove-Item $Folder
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
	WriteVersionToRuntimeJson

	switch -Exact ($DownloadBinary)
	{
		"none"
		{
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

	switch -Exact ($Target)
	{
		"nupkg"
		{
			VSX v142
			Nupkg
		}
		"nupkg-only"
		{
			Nupkg
		}
		"vs2021"
		{
			VSX v143
		}
		"vs2019"
		{
			VSX v142
		}
	}
}
catch
{
	WriteException $_;
}
