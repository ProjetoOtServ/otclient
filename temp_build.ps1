$vcvars = (Get-ChildItem -Path 'C:\Program Files\Microsoft Visual Studio', 'C:\Program Files (x86)\Microsoft Visual Studio' -Filter vcvars64.bat -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
$cmake = (Get-ChildItem -Path 'C:\Program Files\Microsoft Visual Studio', 'C:\Program Files (x86)\Microsoft Visual Studio', 'C:\Program Files\CMake' -Filter cmake.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
if ($vcvars -and $cmake) {
    cmd.exe /c "`"$vcvars`" && `"$cmake`" --build . --config Release"
} else {
    Write-Error "Could not find vcvars64.bat or cmake.exe"
}
