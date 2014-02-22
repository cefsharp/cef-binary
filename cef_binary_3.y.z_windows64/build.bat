msbuild cefclient2010.sln /t:libcef_dll_wrapper:Rebuild /p:Configuration=Release;Platform=x64 /verbosity:Quiet
msbuild cefclient2010.sln /t:libcef_dll_wrapper:Rebuild /p:Configuration=Debug;Platform=x64 /verbosity:Quiet
