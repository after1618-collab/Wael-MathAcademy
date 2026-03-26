@echo off
title WAEL MCP - Starting...
color 0A

echo ========================================
echo    WAEL MCP - Auto Launcher
echo ========================================
echo.

:: 1. Start the Python server
echo [1/2] Starting Python Server...
start "WAEL MCP Server" cmd /k "cd /d "D:\wael mcp" && python mcp_server.py"

:: 2. Wait 5 seconds for server
echo      Waiting for server to start...
timeout /t 5 /nobreak >nul

:: 3. Start Flutter on Chrome
echo [2/2] Starting Flutter App on Chrome...
start "WAEL MCP Flutter" cmd /k "cd /d "D:\wael mcp" && flutter run -d chrome --web-browser-flag=--disable-web-security"

echo.
echo ========================================
echo    Both are starting!
echo ========================================
timeout /t 3