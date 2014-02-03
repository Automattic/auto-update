:wait
choice /t 1 /d n > NUL
tasklist | findstr %WAIT%
if %errorlevel% equ 0 goto wait
start /wait msiexec /i update.msi /quiet