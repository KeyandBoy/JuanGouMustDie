@echo off
chcp 65001 >nul
echo === 卷狗必须死 - 网页导出脚本 ===
echo.
echo 前置条件（首次需要）：
echo 1. 打开 Godot 编辑器 -> 编辑器 -> 管理导出模板 -> 下载并安装
echo    （或访问 https://github.com/godotengine/godot/releases 下载 4.7.2 导出模板）
echo.
set GODOT=E:\computerProgram2\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe
set PROJ=E:\computerProgram2\JuanGouMustDie
set OUT=%PROJ%\export\web

if not exist "%OUT%" mkdir "%OUT%"

echo 正在导出 Web 版本到 %OUT% ...
"%GODOT%" --headless --path "%PROJ%" --export-release "Web" "%OUT%\index.html"
if errorlevel 1 (
  echo 导出失败。请确认已安装 Web 导出模板。
  pause
  exit /b 1
)

echo.
echo 导出完成！目录：%OUT%
echo 部署到 Vercel：
echo   cd "%OUT%"
echo   npx vercel --prod
echo 或将 %OUT% 内容上传到 Vercel 项目。
pause
