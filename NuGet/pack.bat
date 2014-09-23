set version=3.1650.1562-pre4
NuGet pack cef.redist.nuspec -NoPackageAnalysis -Version %version%
rem NuGet pack cef.redist.x86.nuspec -NoPackageAnalysis -Version %version%
rem NuGet pack cef.redist.x64.nuspec -NoPackageAnalysis -Version %version%
NuGet pack cef.sdk.nuspec    -NoPackageAnalysis -Version %version%
