[![Build status](https://ci.appveyor.com/api/projects/status/ggd063qksg6o29i5/branch/master?svg=true)](https://ci.appveyor.com/project/cefsharp/cef-binary/branch/master)

# README

This repository contains a build script that compiles and packages the Chromium Embedded Framework (CEF) binary distribution files for Windows, found at https://cef-builds.spotifycdn.com/index.html

To make it work properly for developers on VS2019 or VS2022 wanting to develop [CefSharp](http://github.com/cefsharp/CefSharp), we need to compile `libcef_dll_wrapper` for ([dynamic linking](https://bitbucket.org/chromiumembedded/cef/wiki/LinkingDifferentRunTimeLibraries)).

The modifications allow us to:

- Re-package and distribute CEF `.dll` and `.pak` files in a piecemeal fashion using http://nuget.org (this is useful for both [Xilium.CefGlue](https://gitlab.com/xiliumhq/chromiumembedded/cefglue) and CefSharp developers and users alike)
- Build `libcef_dll_wrapper.lib`s as mentioned above for [CefSharp](http://github.com/cefsharp/CefSharp)

The CEF Readme.txt file is now included as part of the Nuget packages.

# License

The code is licensed under the same license as the Chromium Embeddded Framework, i.e. the "new BSD" license. The full CEF license text can be found here: [LICENSE.txt](https://bitbucket.org/chromiumembedded/cef/src/master/LICENSE.txt).

Additionally, don't forget to view `chrome://credits/` for additional licences used by Chromium.
