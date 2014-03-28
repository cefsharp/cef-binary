set version=3.1650.1562-pre2
NuGet pack cef.redist.nuspec -NoPackageAnalysis -Version %version%
NuGet pack cef.sdk.nuspec    -NoPackageAnalysis -Version %version%
