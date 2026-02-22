cd /d "%~dp0"
cd ..\..\..\bin\

gmad create -folder "%~dp0\" -out "%~dp0..\__TEMP.gma"
gmpublish create -addon "%~dp0..\__TEMP.gma" -icon "%~dp0icon.jpg"

cd /d "%~dp0"

del ..\__TEMP.gma

pause
