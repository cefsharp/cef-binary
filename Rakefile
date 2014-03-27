desc 'Compile using VS2010, VS2012 and VS2013. Note that this requires all toolchains to be installed and available.'
task :default => [ :vs2012 ]

# TODO: implement
#desc 'Compile using VS2010 tools'
#task :vs2010 do
#end

desc 'Compile using VS2012 tools'
task :vs2012 do
  sh '"C:\Program Files (x86)\Microsoft Visual Studio 11.0\Common7\Tools\vsvars32.bat" && cd cef_binary_3.y.z_windows32 && build'
  sh '"C:\Program Files (x86)\Microsoft Visual Studio 11.0\Common7\Tools\vsvars32.bat" && cd cef_binary_3.y.z_windows64 && build'

  # TODO: change these if needed.
  FileUtils.mkdir_p 'vs2012/x86/Debug'
  FileUtils.mkdir_p 'vs2012/x86/Release'
  FileUtils.mkdir_p 'vs2012/x64/Debug'
  FileUtils.mkdir_p 'vs2012/x64/Release'
  sh 'cp cef_binary_3.y.z_windows32/out/Debug/lib/libcef_dll_wrapper.lib vs2012/x86/Debug'
  sh 'cp cef_binary_3.y.z_windows32/out/Release/lib/libcef_dll_wrapper.lib vs2012/x86/Release'
  sh 'cp cef_binary_3.y.z_windows64/out/Debug/lib/libcef_dll_wrapper.lib vs2012/x64/Debug'
  sh 'cp cef_binary_3.y.z_windows64/out/Release/lib/libcef_dll_wrapper.lib vs2012/x64/Release'

end

# TODO: implement
#desc 'Compile using VS2013 tools'
#task :vs2013 do
#end
