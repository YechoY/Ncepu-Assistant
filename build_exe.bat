@echo off
chcp 65001 >nul
cd /d %~dp0
echo 正在安装依赖...
pip install -r requirements.txt
echo 正在打包...
pyinstaller --noconfirm --clean --onefile --windowed --name NCEPU教务助手 ^
  --add-data "web;web" ^
  --add-data "icon.ico;." ^
  --icon icon.ico ^
  --hidden-import webview.platforms.edgechromium ^
  --hidden-import clr_loader ^
  --hidden-import pythonnet ^
  main.py
echo.
echo 打包完成！可执行文件在 dist\NCEPU教务助手.exe
echo 数据会保存在 exe 旁边的 data 文件夹。
pause
