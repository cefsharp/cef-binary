set version=3.1650.1562-pre4

NuGet pack cef.redist.nuspec -NoPackageAnalysis -Version %version% -Properties Configuration=Debug;DotConfiguration=.Debug;Platform=x86;CPlatform=windows32;
NuGet pack cef.redist.nuspec -NoPackageAnalysis -Version %version% -Properties Configuration=Release;DotConfiguration=.Release;Platform=x86;CPlatform=windows32;
NuGet pack cef.redist.nuspec -NoPackageAnalysis -Version %version% -Properties Configuration=Release;DotConfiguration=;Platform=x86;CPlatform=windows32;

NuGet pack cef.redist.nuspec -NoPackageAnalysis -Version %version% -Properties Configuration=Debug;DotConfiguration=.Debug;Platform=x64;CPlatform=windows64;
NuGet pack cef.redist.nuspec -NoPackageAnalysis -Version %version% -Properties Configuration=Release;DotConfiguration=.Release;Platform=x64;CPlatform=windows64;
NuGet pack cef.redist.nuspec -NoPackageAnalysis -Version %version% -Properties Configuration=Release;DotConfiguration=;Platform=x64;CPlatform=windows64;

NuGet pack cef.sdk.nuspec    -NoPackageAnalysis -Version %version%
