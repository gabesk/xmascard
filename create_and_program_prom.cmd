SET PROM_FILE=TemporaryPromFile
SET PADDED_PROM_FILE=TemporaryPaddedPromFile.bin
SET SIZE_512KB=524288

REM Create the prom file
promgen -w -p bin -o %PROM_FILE% -s 512 -u 0000 %1 -spi
IF %ERRORLEVEL% NEQ 0 GOTO Error

REM Determine how big the file is
FOR /F "usebackq" %%A IN ('%PROM_FILE%.bin') DO set promsize=%%~zA
IF %ERRORLEVEL% NEQ 0 GOTO Error

REM Pad the file
AddBytesToFlash.exe %PROM_FILE%.bin %PADDED_PROM_FILE% %promsize% %SIZE_512KB%
IF %ERRORLEVEL% NEQ 0 GOTO Error

REM Program the flash
mingw32-w64-flashrom-r1781.exe -p buspirate_spi:dev=com5 -w %PADDED_PROM_FILE%
IF %ERRORLEVEL% NEQ 0 GOTO Error

GOTO Done

:Error
ECHO Error programming.

:Done
ECHO Hopefully programmed successfully.
