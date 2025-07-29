@echo off
chcp 65001 >nul
echo Rime词典拼音修正工具
echo =====================

if "%1"=="--help" goto :help
if "%1"=="-h" goto :help
if "%1"=="/?" goto :help

rem 设置默认路径
set INPUT_DIR=input
set OUTPUT_DIR=output

rem 检查输入目录
if not exist "%INPUT_DIR%" (
    echo 错误: 输入目录 "%INPUT_DIR%" 不存在
    echo 请创建输入目录并放入要处理的词典文件
    echo.
    echo 按任意键退出...
    pause >nul
    exit /b 1
)

rem 创建输出目录
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

rem 运行程序
echo 正在处理词典文件...
echo 输入目录: %INPUT_DIR%
echo 输出目录: %OUTPUT_DIR%
echo.

rime-dict-processor.exe -i "%INPUT_DIR%" -o "%OUTPUT_DIR%"

if %ERRORLEVEL% == 0 (
    echo.
    echo 处理完成！
    echo 结果保存在: %OUTPUT_DIR%
) else (
    echo.
    echo 处理过程中出现错误
)

echo.
echo 按任意键退出...
pause >nul
exit /b 0

:help
echo.
echo 使用说明:
echo   run.bat                 - 使用默认设置处理词典
echo   run.bat --help          - 显示此帮助信息
echo.
echo 目录结构:
echo   input/                  - 放置要处理的词典文件
echo   output/                 - 处理结果输出目录
echo   pinyin_data/           - 自定义拼音数据(可选)
echo.
echo 支持的文件格式:
echo   - .dict.yaml           - 普通词典格式
echo   - .userdb.txt          - 用户词典格式
echo.
pause
exit /b 0
