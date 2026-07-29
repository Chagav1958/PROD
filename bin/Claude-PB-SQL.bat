@echo off
REM ============================================
REM Claude Code для PowerBuilder и Sybase SQL
REM Запуск с MCP-серверами (sybase-docs, Jira)
REM ============================================
REM Перед первым запуском выполнить: claude auth login
REM ============================================

set CLAUDE_PROJECT_DIR=C:\AIS\AI\Prod

echo === Claude Code AI ===
echo PowerBuilder / Sybase ASE SQL
echo MCP: sybase-docs + Jira
echo.
echo Команды для начала:
echo   /add-dir C:\AIS\AI\Prod\PB_Current    
echo   /add-dir C:\AIS\AI\Prod\BD\dev_golden\golden
echo.
echo Быстрые задачи:
echo   claude -p "проанализируй usp_agent_policy_list_v1"
echo   claude -p "найди ошибки в файле C:\AIS\...\usp_xxx.sql"
echo ============================================
echo.

claude --mcp-config "C:\AIS\AI\Prod\.mcp.json" --add-dir "C:\AIS\AI\Prod\PB_Current" --add-dir "C:\AIS\AI\Prod\BD\dev_golden\golden" --add-dir "C:\AIS\AI\Prod\scripts" %*
