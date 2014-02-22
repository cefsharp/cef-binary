msbuild cefclient2010.sln /t:libcef_dll_wrapper:Rebuild /p:Configuration=Release;Platform=Win32 /verbosity:Quiet
msbuild cefclient2010.sln /t:libcef_dll_wrapper:Rebuild /p:Configuration=Debug;Platform=Win32 /verbosity:Quiet
