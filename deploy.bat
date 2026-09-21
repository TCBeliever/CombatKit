@echo off
rem Copy this project into the WoW AddOns folder for local testing, then /reload in game.
rem The core goes to CombatKit, every folder under Modules to CombatKit_<Name>.
rem /MIR keeps each target an exact copy, so files removed here disappear there too.
set SRC=%~dp0
set ADDONS=F:\World of Warcraft\_retail_\Interface\AddOns

robocopy "%SRC%." "%ADDONS%\CombatKit" *.toc *.lua /MIR /XD .git docs tests Modules /NFL /NDL /NJH /NJS /NP
if %ERRORLEVEL% GEQ 8 goto failed

for /d %%M in ("%SRC%Modules\*") do (
  robocopy "%%M" "%ADDONS%\CombatKit_%%~nxM" *.toc *.lua /MIR /NFL /NDL /NJH /NJS /NP
  if errorlevel 8 goto failed
)

echo CombatKit deployed to "%ADDONS%"
exit /b 0

:failed
echo Copy failed.
exit /b 1
