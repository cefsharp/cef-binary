[![Build status](https://ci.appveyor.com/api/projects/status/ggd063qksg6o29i5/branch/master?svg=true)](https://ci.appveyor.com/project/cefsharp/cef-binary/branch/master)

# README

This is a repackaging fork of the Chromium Embedded Framework (CEF) binary distribution files for Windows, found at https://cef-builds.spotifycdn.com/index.html, into [these NuGet packages](https://www.nuget.org/packages?q=Id%3A%22cef.redist%22%2C%22cef.sdk%22)

To make it work properly for developers on VS2013 or VS2015 wanting to develop [CefSharp](http://github.com/cefsharp/CefSharp), we need to do some local modifications ([use dynamic linking](https://bitbucket.org/chromiumembedded/cef/wiki/LinkingDifferentRunTimeLibraries)) to make CefSharp.Core compile properly. This purpose of this repository is to track and maintain these modifications as well as tooling for maintaining the NuGet packages.

The modifications allow us to:

- Re-package and distribute CEF `.dll` and `.pak` files in a piecemeal fashion using http://nuget.org (this is useful for both [Xilium.CefGlue](https://bitbucket.org/xilium/xilium.cefglue) and CefSharp developers and users alike)
- Build `libcef_dll_wrapper.lib`s as mentioned above for [CefSharp](http://github.com/cefsharp/CefSharp)
- Have a place to pick CEF `include` files for easy inclusion downstream (by `git submodule` vendor folders etc.)

The original README for CEF can be found here: [README.txt](README.txt). It has some useful details about which CEF pieces are needed for what (e.g. browser developer tools, language support, different HTML5 features, WebGL support etc.)

# Architecture

Note to self: Add a diagram here based on: http://codepen.io/jornh/full/Iyebk explaining that this is the red layer with the native code from the upstream CEF (and Chromium projects)

TODO: Explain each of the red pieces along the lines of this rough plan (subject to change):
Foundation z: NuGets

- C.F.Base.x64|Win32 ... (~ Bcl. Xxx ) .... 
- C.Foundation.Res.Lang
- C.Foundation.Res.Dev

- C.Foundation.WebGL (incl d*dxxxx43|46)
- C.F.MDwrapper

  ## Easy

- C.F.Bundle.x64(NoLang)
- C.F.Bundle.Win32

- CS.Core
- CS.Wpf


# License

The code is licensed under the same license as the Chromium Embeddded Framework, i.e. the "new BSD" license. The full CEF license text can be found here: [LICENSE.txt](LICENSE.txt).

Additionally, don't forget to view `chrome://credits/` for additional licences used by Chromium.
