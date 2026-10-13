@echo off
setlocal EnableDelayedExpansion
title Local AI Launcher
color 0A
set "CFG=%~dp0local_ai_model.txt"

:: ============================================================
::  LOCAL AI LAUNCHER  -  runs AI models 100 percent on your PC
::  Powered by Ollama. No internet needed after a model is downloaded.
:: ============================================================

:check
where ollama >nul 2>&1
if not errorlevel 1 goto ready
if exist "%LOCALAPPDATA%\Programs\Ollama\ollama.exe" goto addpath

cls
echo Ollama is not installed. It is the engine that runs the AI on your PC.
echo.
choice /c YN /m "Install it now with winget"
if errorlevel 2 goto manual
winget install -e --id Ollama.Ollama --accept-package-agreements --accept-source-agreements
if errorlevel 1 goto manual
goto check

:manual
echo.
echo Opening the Ollama download page. Install it, then run this file again.
start "" https://ollama.com/download
pause
exit /b

:addpath
set "PATH=%PATH%;%LOCALAPPDATA%\Programs\Ollama"

:ready
ollama list >nul 2>&1
if not errorlevel 1 goto hw
echo Starting the Ollama engine...
start "Ollama Engine" /min ollama serve
timeout /t 5 >nul

:hw
set RAM=8
for /f %%i in ('powershell -NoProfile -Command "[math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB)"') do set RAM=%%i
set "GPU=Unknown"
for /f "delims=" %%i in ('powershell -NoProfile -Command "(Get-CimInstance Win32_VideoController | Select-Object -First 1).Name"') do set "GPU=%%i"

set REC=llama3.2:3b
if %RAM% LSS 6 set REC=llama3.2:1b
if %RAM% GEQ 10 set REC=qwen2.5:7b
if %RAM% GEQ 24 set REC=qwen2.5:14b

set "MODEL=%REC%"
if exist "%CFG%" set /p MODEL=<"%CFG%"

:menu
cls
echo ==============================================
echo               LOCAL AI LAUNCHER
echo ==============================================
echo  RAM: %RAM% GB     GPU: %GPU%
echo  Recommended model for this PC: %REC%
echo  Current model: %MODEL%
echo ==============================================
echo.
echo   [1] Chat with the AI
echo   [2] Pick a model from the list
echo   [3] Download any model by name
echo   [4] Show installed models
echo   [5] Delete a model
echo   [6] Create a custom AI persona
echo   [7] Local API info for your own apps
echo   [8] Let the AI type for me, 100 words, letters only
echo   [9] Quit
echo.
choice /c 123456789 /n /m "Choose: "
set C=%errorlevel%
if %C%==1 goto chat
if %C%==2 goto pick
if %C%==3 goto download
if %C%==4 goto installed
if %C%==5 goto delete
if %C%==6 goto persona
if %C%==7 goto api
if %C%==8 goto typeai
exit /b

:ensure
ollama list | findstr /i /b /c:"%MODEL%" >nul
if not errorlevel 1 exit /b 0
echo.
echo Model %MODEL% is not downloaded yet. Downloading now...
ollama pull %MODEL%
exit /b %errorlevel%

:chat
call :ensure
if errorlevel 1 (
    echo Download failed. Check the model name and your connection.
    pause
    goto menu
)
cls
echo Chatting with %MODEL%
echo Type /bye to leave the chat. Type /? for more commands.
echo Tip: end a line with triple quotes to write multi-line messages.
echo.
ollama run %MODEL%
goto menu

:pick
cls
echo Choose a model. Bigger means smarter but needs more RAM.
echo.
echo   [1] llama3.2:1b      tiny and very fast, about 4 GB RAM
echo   [2] llama3.2:3b      fast all-rounder, about 6 GB RAM
echo   [3] gemma2:2b        small and clever, about 6 GB RAM
echo   [4] qwen2.5:7b       strong general model, about 10 GB RAM
echo   [5] llama3.1:8b      strong general model, about 12 GB RAM
echo   [6] qwen2.5-coder:7b best for programming, about 10 GB RAM
echo   [7] deepseek-r1:8b   step-by-step reasoning, about 12 GB RAM
echo   [8] qwen2.5:14b      very capable, about 24 GB RAM
echo   [9] Back
echo.
choice /c 123456789 /n /m "Choose: "
set P=%errorlevel%
if %P%==9 goto menu
if %P%==1 set MODEL=llama3.2:1b
if %P%==2 set MODEL=llama3.2:3b
if %P%==3 set MODEL=gemma2:2b
if %P%==4 set MODEL=qwen2.5:7b
if %P%==5 set MODEL=llama3.1:8b
if %P%==6 set MODEL=qwen2.5-coder:7b
if %P%==7 set MODEL=deepseek-r1:8b
if %P%==8 set MODEL=qwen2.5:14b
>"%CFG%" echo %MODEL%
goto menu

:download
echo.
echo Browse models at https://ollama.com/library
set "NM="
set /p NM=Model name, for example mistral or phi3:mini :
if "%NM%"=="" goto menu
ollama pull %NM%
if errorlevel 1 (
    echo Download failed.
    pause
    goto menu
)
set "MODEL=%NM%"
>"%CFG%" echo %MODEL%
echo Done. %MODEL% is now your current model.
pause
goto menu

:installed
cls
ollama list
echo.
pause
goto menu

:delete
cls
ollama list
echo.
set "DM="
set /p DM=Model to delete, exact name, or blank to cancel: 
if "%DM%"=="" goto menu
ollama rm %DM%
pause
goto menu

:persona
cls
echo Create a custom AI persona on top of %MODEL%.
echo.
set "PN="
set /p PN=Persona name, lowercase, no spaces, for example pirate: 
if "%PN%"=="" goto menu
set "SYS="
set /p SYS=Describe how the AI should behave: 
if "!SYS!"=="" goto menu
call :ensure
if errorlevel 1 (
    echo Could not get the base model.
    pause
    goto menu
)
set "MF=%TEMP%\local_ai_modelfile.txt"
>"%MF%" echo FROM %MODEL%
>>"%MF%" echo PARAMETER temperature 0.7
>>"%MF%" echo SYSTEM """!SYS!"""
ollama create %PN% -f "%MF%"
if errorlevel 1 (
    echo Could not create the persona.
    pause
    goto menu
)
set "MODEL=%PN%"
>"%CFG%" echo %MODEL%
echo.
echo Persona %PN% created and selected. Choose option 1 to chat.
pause
goto menu

:api
cls
echo While Ollama is running, it offers a local API on your PC only:
echo.
echo   Native API:        http://localhost:11434/api
echo   OpenAI-compatible: http://localhost:11434/v1
echo.
echo Point any app or script at those addresses and use the model name
echo %MODEL%. No API key is needed.
echo.
pause
goto menu

:typeai
call :ensure
if errorlevel 1 (
    echo Could not get the model.
    pause
    goto menu
)
cls
echo The AI will write a reply and TYPE it into whichever window you click on.
echo.
echo   Limits: 100 words maximum, letters A-Z and spaces only.
echo   You see a preview first, then a 5 second countdown.
echo   Hold the Esc key at any time to stop the typing.
echo.
set "PR="
set /p PR=What should the AI write? 
if "!PR!"=="" goto menu
set "AI_MODEL=%MODEL%"
set "AI_PROMPT=!PR!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s = Get-Content -LiteralPath '%~f0' -Raw; iex ($s.Substring($s.IndexOf('#PS'+'-START') + 9))"
pause
goto menu

#PS-START
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System.Runtime.InteropServices;
public class KeyCheck {
    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);
}
'@

$maxWords = 100

function Run-Typer {
    $model  = $env:AI_MODEL
    $prompt = $env:AI_PROMPT

    Write-Host "`nThinking..." -ForegroundColor Cyan
    $ask = "Write the following using plain English words only. Do not use numbers, punctuation, symbols, emojis or line breaks. Use at most $maxWords words. Task: $prompt"
    $body = @{ model = $model; prompt = $ask; stream = $false } | ConvertTo-Json
    try {
        $r = Invoke-RestMethod -Uri 'http://localhost:11434/api/generate' -Method Post `
            -ContentType 'application/json; charset=utf-8' `
            -Body ([Text.Encoding]::UTF8.GetBytes($body))
    } catch {
        Write-Host "Could not reach the AI: $_" -ForegroundColor Red
        return
    }

    $text = [string]$r.response
    $text = [regex]::Replace($text, '(?s)<think>.*?</think>', '')
    $text = [regex]::Replace($text, "[\u2019']", '')
    $text = [regex]::Replace($text, '[^A-Za-z]+', ' ')
    $words = @($text.Trim() -split ' ' | Where-Object { $_ } | Select-Object -First $maxWords)
    $final = $words -join ' '

    if (-not $final) {
        Write-Host 'The AI gave nothing usable. Try again.' -ForegroundColor Yellow
        return
    }

    Write-Host "`nPreview ($($words.Count) words):" -ForegroundColor Green
    Write-Host $final
    Write-Host ''
    $ok = Read-Host 'Type this now? (y/n)'
    if ($ok -ne 'y') { Write-Host 'Cancelled.'; return }

    foreach ($i in 5..1) {
        Write-Host "Click the window you want to type into... starting in $i" -ForegroundColor Yellow
        Start-Sleep -Seconds 1
    }

    foreach ($ch in $final.ToCharArray()) {
        if ([KeyCheck]::GetAsyncKeyState(0x1B) -band 0x8000) {
            Write-Host 'Stopped with Esc.' -ForegroundColor Red
            return
        }
        if ($ch -match '[A-Za-z ]') {
            [System.Windows.Forms.SendKeys]::SendWait([string]$ch)
        }
        Start-Sleep -Milliseconds 40
    }
    Write-Host 'Done.' -ForegroundColor Green
}

Run-Typer
