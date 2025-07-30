#!/bin/bash
# -*- coding: utf-8 -*-
# Wine交叉编译脚本 - 将Python项目打包为Windows静态可执行文件
# 目标平台: Windows x64
# 编译平台: Debian 12
# 日期: 2025-07-29

set -e  # 遇到错误立即退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
WINE_PREFIX="$HOME/.wine"
PYTHON_VERSION="3.11.9"
PROJECT_NAME="rime-dict-processor"
MAIN_SCRIPT="src/main.py"
OUTPUT_DIR="dist"
WINE_DRIVE_C="$WINE_PREFIX/drive_c"
PYTHON_PATH="$WINE_DRIVE_C/Python311"

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检测是否需要sudo权限
needs_sudo() {
    # 如果当前用户是root，不需要sudo
    if [ "$EUID" -eq 0 ]; then
        return 1
    fi
    
    # 在GitHub Actions或其他CI环境中，通常需要sudo
    if [ "$CI" = "true" ] || [ "$GITHUB_ACTIONS" = "true" ]; then
        return 0
    fi
    
    # 检查是否有sudo命令且当前用户在sudoers中
    if command -v sudo &> /dev/null && sudo -n true 2>/dev/null; then
        return 0
    fi
    
    # 默认尝试不使用sudo
    return 1
}

# 智能执行命令（根据需要添加sudo）
run_with_sudo() {
    if needs_sudo; then
        log_info "使用sudo执行: $*"
        sudo "$@"
    else
        log_info "直接执行: $*"
        "$@"
    fi
}

# 检查命令是否存在
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "命令 '$1' 未找到，请先安装"
        exit 1
    fi
}

# 安装系统依赖
install_system_deps() {
    # 如果在CI环境中，检查关键依赖是否已存在
    if [ "$CI" = "true" ] || [ "$GITHUB_ACTIONS" = "true" ]; then
        log_info "检测到CI环境，检查预装依赖..."
        
        # 检查关键命令是否已存在
        local missing_deps=()
        
        # 检查Wine
        if ! command -v wine &> /dev/null; then
            missing_deps+=("wine64")
        fi
        
        # 检查基本工具
        if ! command -v wget &> /dev/null; then
            missing_deps+=("wget")
        fi
        
        if ! command -v xvfb-run &> /dev/null; then
            missing_deps+=("xvfb")
        fi
        
        # 如果关键依赖都存在，跳过完整安装
        if [ ${#missing_deps[@]} -eq 0 ]; then
            log_success "CI环境依赖检查完成，跳过系统依赖安装"
            # 仍需检查必要的命令
            check_command "wine"
            check_command "wget"
            return
        else
            log_info "缺少依赖: ${missing_deps[*]}，继续安装..."
        fi
    fi
    
    log_info "检查并安装系统依赖..."
    
    # 更新包列表并安装基本依赖
    run_with_sudo apt-get update
    run_with_sudo apt-get install -y \
        wine64 \
        cabextract \
        p7zip-full \
        curl \
        wget \
        xvfb \
        unzip
    
    # 手动安装winetricks（如果不存在）
    if ! command -v winetricks &> /dev/null; then
        log_info "手动安装winetricks..."
        wget -O /tmp/winetricks https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
        chmod +x /tmp/winetricks
        run_with_sudo mv /tmp/winetricks /usr/local/bin/
        log_success "winetricks安装完成"
    fi
    
    # 检查必要的命令
    check_command "wine"
    check_command "wget"
    check_command "curl"
    check_command "winetricks"
    
    log_success "系统依赖安装完成"
}

# 初始化Wine环境
init_wine() {
    log_info "初始化Wine环境..."
    
    # 设置Wine为64位模式
    export WINEARCH=win64
    export WINEPREFIX="$WINE_PREFIX"
    export DISPLAY=${DISPLAY:-:0.0}
    
    # 创建Wine前缀
    if [ ! -d "$WINE_PREFIX" ]; then
        log_info "创建Wine前缀..."
        # 使用xvfb运行winecfg以避免GUI问题
        xvfb-run -a winecfg /v win10 2>/dev/null || {
            log_warning "winecfg失败，尝试基本初始化..."
            wine wineboot --init
        }
    fi
    
    # 等待Wine初始化完成
    log_info "等待Wine初始化完成..."
    sleep 5
    
    # 安装必要的Windows组件（简化版）
    log_info "安装Windows组件..."
    # 只安装最基本的运行时，避免GUI交互
    xvfb-run -a winetricks -q vcrun2019 2>/dev/null || {
        log_warning "vcrun2019安装失败，尝试vcrun2015..."
        xvfb-run -a winetricks -q vcrun2015 2>/dev/null || {
            log_warning "Visual C++ Runtime安装失败，继续构建..."
        }
    }
    
    log_success "Wine环境初始化完成"
}

# 安装Python到Wine环境
install_python_wine() {
    log_info "在Wine环境中安装Python $PYTHON_VERSION..."
    
    # 设置Wine环境变量
    export WINEARCH=win64
    export WINEPREFIX="$WINE_PREFIX"
    export DISPLAY=${DISPLAY:-:0.0}
    
    # 检查多个可能的Python安装路径
    PYTHON_PATHS=(
        "$WINE_DRIVE_C/Python311/python.exe"
        "$WINE_DRIVE_C/Python$PYTHON_VERSION/python.exe"
        "$WINE_DRIVE_C/users/$USER/AppData/Local/Programs/Python/Python311/python.exe"
        "$WINE_DRIVE_C/Program Files/Python311/python.exe"
        "$WINE_DRIVE_C/Program Files (x86)/Python311/python.exe"
    )
    
    # 检查是否已经安装
    FOUND_PYTHON=""
    for path in "${PYTHON_PATHS[@]}"; do
        if [ -f "$path" ] && wine "$path" --version 2>/dev/null | grep -q "Python"; then
            FOUND_PYTHON="$path"
            PYTHON_PATH="$(dirname "$path")"
            log_warning "Python已安装: $FOUND_PYTHON"
            return
        fi
    done
    
    # 下载Python安装包
    PYTHON_INSTALLER="python-$PYTHON_VERSION-amd64.exe"
    if [ ! -f "$PYTHON_INSTALLER" ]; then
        log_info "下载Python安装包..."
        wget "https://www.python.org/ftp/python/$PYTHON_VERSION/$PYTHON_INSTALLER" || {
            log_error "Python下载失败"
            exit 1
        }
    fi
    
    # 尝试多种安装方法
    log_info "尝试安装Python（方法1：InstallAllUsers）..."
    if xvfb-run -a wine "$PYTHON_INSTALLER" /quiet InstallAllUsers=1 PrependPath=1 Include_test=0 2>/dev/null; then
        sleep 20
    else
        log_warning "方法1失败，尝试方法2（当前用户安装）..."
        if xvfb-run -a wine "$PYTHON_INSTALLER" /quiet PrependPath=1 Include_test=0 2>/dev/null; then
            sleep 20
        else
            log_warning "方法2失败，尝试方法3（手动解压）..."
            # 尝试手动解压Python嵌入式版本
            install_python_embedded
            return
        fi
    fi
    
    # 验证安装
    log_info "验证Python安装..."
    FOUND_PYTHON=""
    for i in {1..3}; do
        for path in "${PYTHON_PATHS[@]}"; do
            if [ -f "$path" ]; then
                log_info "找到Python文件: $path"
                if wine "$path" --version 2>/dev/null | grep -q "Python"; then
                    FOUND_PYTHON="$path"
                    PYTHON_PATH="$(dirname "$path")"
                    log_success "Python安装成功: $FOUND_PYTHON"
                    return
                fi
            fi
        done
        log_info "等待Python安装完成... ($i/3)"
        sleep 10
    done
    
    log_error "Python安装失败，尝试安装嵌入式版本..."
    install_python_embedded
}

# 安装Python嵌入式版本作为备选方案
install_python_embedded() {
    log_info "安装Python嵌入式版本..."
    
    PYTHON_EMBED_VERSION="3.11.9"
    PYTHON_EMBED_ZIP="python-$PYTHON_EMBED_VERSION-embed-amd64.zip"
    PYTHON_EMBED_DIR="$WINE_DRIVE_C/Python311Embed"
    
    # 下载嵌入式Python
    if [ ! -f "$PYTHON_EMBED_ZIP" ]; then
        log_info "下载Python嵌入式版本..."
        wget "https://www.python.org/ftp/python/$PYTHON_EMBED_VERSION/$PYTHON_EMBED_ZIP" || {
            log_error "Python嵌入式版本下载失败"
            exit 1
        }
    fi
    
    # 解压到Wine目录
    log_info "解压Python嵌入式版本..."
    rm -rf "$PYTHON_EMBED_DIR"
    mkdir -p "$PYTHON_EMBED_DIR"
    unzip -q "$PYTHON_EMBED_ZIP" -d "$PYTHON_EMBED_DIR"
    
    # 启用pip支持
    log_info "配置Python嵌入式版本..."
    if [ -f "$PYTHON_EMBED_DIR/python311._pth" ]; then
        # 取消注释import site行
        sed -i 's/^#import site/import site/' "$PYTHON_EMBED_DIR/python311._pth"
    fi
    
    # 下载get-pip.py
    log_info "安装pip..."
    wget -O "$PYTHON_EMBED_DIR/get-pip.py" https://raw.githubusercontent.com/pypa/get-pip/refs/heads/main/public/get-pip.py || {
        log_error "get-pip.py下载失败"
        exit 1
    }
    
    # 安装pip
    wine "$PYTHON_EMBED_DIR/python.exe" "$PYTHON_EMBED_DIR/get-pip.py" 2>/dev/null || {
        log_warning "pip安装可能有问题，继续..."
    }
    
    # 验证嵌入式Python
    if wine "$PYTHON_EMBED_DIR/python.exe" --version 2>/dev/null | grep -q "Python"; then
        PYTHON_PATH="$PYTHON_EMBED_DIR"
        log_success "Python嵌入式版本安装成功: $PYTHON_PATH/python.exe"
    else
        log_error "Python嵌入式版本安装失败"
        exit 1
    fi
}

# 安装Python依赖包
install_python_deps() {
    log_info "安装Python依赖包..."
    
    # 设置Wine环境变量
    export WINEARCH=win64
    export WINEPREFIX="$WINE_PREFIX"
    export DISPLAY=${DISPLAY:-:0.0}
    
    # 找到Python可执行文件
    PYTHON_EXE="$PYTHON_PATH/python.exe"
    if [ ! -f "$PYTHON_EXE" ]; then
        log_error "找不到Python可执行文件: $PYTHON_EXE"
        exit 1
    fi
    
    # 验证Python工作正常
    log_info "验证Python工作状态..."
    if ! wine "$PYTHON_EXE" --version 2>/dev/null | grep -q "Python"; then
        log_error "Python无法正常运行"
        exit 1
    fi
    
    # 尝试升级pip
    log_info "升级pip..."
    wine "$PYTHON_EXE" -m pip install --upgrade pip 2>/dev/null || {
        log_warning "pip升级失败，尝试安装pip..."
        # 如果是嵌入式版本，可能需要重新安装pip
        if [ -f "$PYTHON_PATH/get-pip.py" ]; then
            wine "$PYTHON_EXE" "$PYTHON_PATH/get-pip.py" --force-reinstall 2>/dev/null || {
                log_warning "pip重新安装失败，继续..."
            }
        fi
    }
    
    # 安装PyInstaller
    log_info "安装PyInstaller..."
    wine "$PYTHON_EXE" -m pip install pyinstaller 2>/dev/null || {
        log_warning "PyInstaller安装失败，尝试使用--user参数..."
        wine "$PYTHON_EXE" -m pip install --user pyinstaller || {
            log_error "PyInstaller安装完全失败"
            exit 1
        }
    }
    
    log_success "Python依赖包安装完成"
}

# 准备构建文件
prepare_build() {
    log_info "准备构建文件..."
    
    # 清理旧的构建文件
    rm -rf "$OUTPUT_DIR" build *.spec
    
    # 创建输出目录
    mkdir -p "$OUTPUT_DIR"
    
    # 检查主脚本是否存在
    if [ ! -f "$MAIN_SCRIPT" ]; then
        log_error "主脚本 '$MAIN_SCRIPT' 不存在"
        exit 1
    fi
    
    log_success "构建文件准备完成"
}

# 创建PyInstaller spec文件
create_spec_file() {
    log_info "创建PyInstaller spec文件..."
    
    cat > "${PROJECT_NAME}.spec" << EOF
# -*- mode: python ; coding: utf-8 -*-

import os
import sys
from PyInstaller.utils.hooks import collect_data_files, collect_submodules

# 添加当前目录到路径
sys.path.insert(0, os.path.abspath('.'))
sys.path.insert(0, os.path.abspath('src'))

# 收集数据文件
datas = []

# 自动收集pypinyin的所有数据文件
try:
    pypinyin_datas = collect_data_files('pypinyin')
    datas.extend(pypinyin_datas)
    print(f"自动收集到 {len(pypinyin_datas)} 个pypinyin数据文件")
except Exception as e:
    print(f"自动收集pypinyin数据文件失败: {e}")

# 手动添加pypinyin的关键文件
pypinyin_src = os.path.join('src', 'pypinyin')
if os.path.exists(pypinyin_src):
    # 关键的JSON字典文件
    json_files = ['pinyin_dict.json', 'phrases_dict.json']
    for json_file in json_files:
        src_path = os.path.join(pypinyin_src, json_file)
        if os.path.exists(src_path):
            datas.append((src_path, 'pypinyin'))
            print(f"手动添加: {json_file}")
    
    # 添加所有Python文件和数据文件
    for root, dirs, files in os.walk(pypinyin_src):
        # 跳过__pycache__目录
        dirs[:] = [d for d in dirs if d != '__pycache__']
        
        for file in files:
            if file.endswith(('.json', '.py', '.pyi', '.txt', '.dat', '.typed')):
                src_file = os.path.join(root, file)
                # 计算相对路径
                rel_root = os.path.relpath(root, 'src')
                datas.append((src_file, rel_root))

# 自动收集tqdm的所有数据文件
try:
    tqdm_datas = collect_data_files('tqdm')
    datas.extend(tqdm_datas)
    print(f"自动收集到 {len(tqdm_datas)} 个tqdm数据文件")
except Exception as e:
    print(f"自动收集tqdm数据文件失败: {e}")

# 手动添加tqdm的所有文件
tqdm_src = os.path.join('src', 'tqdm')
if os.path.exists(tqdm_src):
    for root, dirs, files in os.walk(tqdm_src):
        # 跳过__pycache__目录
        dirs[:] = [d for d in dirs if d != '__pycache__']
        
        for file in files:
            if file.endswith(('.py', '.pyi', '.txt', '.sh', '.1')):
                src_file = os.path.join(root, file)
                rel_root = os.path.relpath(root, 'src')
                datas.append((src_file, rel_root))

# 添加项目数据文件
if os.path.exists('src/pinyin_data'):
    datas.append(('src/pinyin_data', 'pinyin_data'))

# 去重数据文件列表
seen = set()
unique_datas = []
for item in datas:
    if item not in seen:
        seen.add(item)
        unique_datas.append(item)
datas = unique_datas

print(f"总共包含 {len(datas)} 个数据文件")

# 收集隐式导入
hiddenimports = []

# 自动收集pypinyin子模块
try:
    pypinyin_modules = collect_submodules('pypinyin')
    hiddenimports.extend(pypinyin_modules)
    print(f"自动收集到 {len(pypinyin_modules)} 个pypinyin子模块")
except Exception as e:
    print(f"自动收集pypinyin子模块失败: {e}")

# 自动收集tqdm子模块
try:
    tqdm_modules = collect_submodules('tqdm')
    hiddenimports.extend(tqdm_modules)
    print(f"自动收集到 {len(tqdm_modules)} 个tqdm子模块")
except Exception as e:
    print(f"自动收集tqdm子模块失败: {e}")

# 手动添加关键的隐式导入
manual_imports = [
    'pypinyin',
    'pypinyin.pinyin_dict',
    'pypinyin.phrases_dict',
    'pypinyin.core',
    'pypinyin.standard',
    'pypinyin.utils',
    'pypinyin.compat',
    'pypinyin.constants',
    'pypinyin.converter',
    'pypinyin.phonetic_symbol',
    'pypinyin.runner',
    'pypinyin.contrib',
    'pypinyin.contrib.tone_convert',
    'pypinyin.contrib.neutral_tone',
    'pypinyin.contrib.tone_sandhi',
    'pypinyin.style',
    'pypinyin.seg',
    'tqdm',
    'tqdm.auto',
    'tqdm.std',
    'json',
    're',
    'os',
    'shutil',
    'collections',
    'rime_processor_embedded',
]

hiddenimports.extend(manual_imports)

# 去重隐式导入列表
hiddenimports = list(set(hiddenimports))
print(f"总共包含 {len(hiddenimports)} 个隐式导入")

a = Analysis(
    ['$MAIN_SCRIPT'],
    pathex=['.', 'src'],
    binaries=[],
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='$PROJECT_NAME',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    version='version_info.txt',
    icon=None,
)
EOF
    
    log_success "PyInstaller spec文件创建完成"
}

# 创建版本信息文件
create_version_info() {
    log_info "创建版本信息文件..."
    
    cat > "version_info.txt" << EOF
VSVersionInfo(
  ffi=FixedFileInfo(
filevers=(1, 0, 0, 0),
prodvers=(1, 0, 0, 0),
mask=0x3f,
flags=0x0,
OS=0x40004,
fileType=0x1,
subtype=0x0,
date=(0, 0)
),
  kids=[
StringFileInfo(
  [
  StringTable(
    u'040904B0',
    [StringStruct(u'CompanyName', u'Rime Dict Processor'),
    StringStruct(u'FileDescription', u'Rime词典拼音修正工具'),
    StringStruct(u'FileVersion', u'1.0.0.0'),
    StringStruct(u'InternalName', u'$PROJECT_NAME'),
    StringStruct(u'LegalCopyright', u'Copyright (C) 2025'),
    StringStruct(u'OriginalFilename', u'$PROJECT_NAME.exe'),
    StringStruct(u'ProductName', u'Rime Dict Processor'),
    StringStruct(u'ProductVersion', u'1.0.0.0')])
  ]), 
VarFileInfo([VarStruct(u'Translation', [1033, 1200])])
  ]
)
EOF
    
    log_success "版本信息文件创建完成"
}

# 使用PyInstaller构建
build_executable() {
    log_info "使用PyInstaller构建可执行文件..."
    
    # 设置Wine环境变量
    export WINEARCH=win64
    export WINEPREFIX="$WINE_PREFIX"
    export DISPLAY=${DISPLAY:-:0.0}
    
    # 找到Python可执行文件
    PYTHON_EXE="$PYTHON_PATH/python.exe"
    if [ ! -f "$PYTHON_EXE" ]; then
        log_error "找不到Python可执行文件: $PYTHON_EXE"
        exit 1
    fi
    
    # 验证PyInstaller可用
    log_info "验证PyInstaller..."
    if ! wine "$PYTHON_EXE" -m PyInstaller --version 2>/dev/null; then
        log_error "PyInstaller不可用"
        exit 1
    fi
    
    # 复制嵌入式处理模块到Python路径
    log_info "复制嵌入式处理模块..."
    cp src/rime_processor_embedded.py "$PYTHON_PATH/"
    
    # 复制pypinyin和tqdm模块到Python路径
    log_info "复制pypinyin和tqdm模块..."
    cp -r src/pypinyin "$PYTHON_PATH/"
    cp -r src/tqdm "$PYTHON_PATH/"
    
    # 确保pypinyin的JSON文件存在
    if [ ! -f "$PYTHON_PATH/pypinyin/pinyin_dict.json" ]; then
        log_error "pypinyin字典文件缺失"
        exit 1
    fi
    
    log_info "Python模块准备完成"
    
    # 运行PyInstaller
    log_info "开始编译，这可能需要几分钟..."
    wine "$PYTHON_EXE" -m PyInstaller \
        --clean \
        --noconfirm \
        --onefile \
        --console \
        --distpath="$OUTPUT_DIR" \
        --workpath="build" \
        --specpath="." \
        "${PROJECT_NAME}.spec" 2>/dev/null || {
        log_warning "PyInstaller构建可能有问题，检查输出..."
        
        # 尝试不使用spec文件的简单构建
        log_info "尝试简化构建..."
        wine "$PYTHON_EXE" -m PyInstaller \
            --clean \
            --noconfirm \
            --onefile \
            --console \
            --distpath="$OUTPUT_DIR" \
            --workpath="build" \
            --add-data="src/pypinyin;pypinyin" \
            --add-data="src/tqdm;tqdm" \
            --add-data="src/pinyin_data;pinyin_data" \
            --hidden-import=pypinyin \
            --hidden-import=pypinyin.pinyin_dict \
            --hidden-import=pypinyin.phrases_dict \
            --hidden-import=pypinyin.core \
            --hidden-import=pypinyin.standard \
            --hidden-import=pypinyin.utils \
            --hidden-import=pypinyin.compat \
            --hidden-import=pypinyin.constants \
            --hidden-import=pypinyin.converter \
            --hidden-import=pypinyin.phonetic_symbol \
            --hidden-import=pypinyin.runner \
            --hidden-import=tqdm \
            --hidden-import=tqdm.auto \
            --hidden-import=tqdm.std \
            --hidden-import=json \
            --hidden-import=re \
            --hidden-import=os \
            --hidden-import=shutil \
            --hidden-import=rime_processor_embedded \
            "$MAIN_SCRIPT" || {
            log_error "PyInstaller构建失败"
            exit 1
        }
    }
    
    # 检查构建结果
    EXE_FILE="$OUTPUT_DIR/${PROJECT_NAME}.exe"
    if [ ! -f "$EXE_FILE" ]; then
        # 尝试查找其他可能的输出文件
        POSSIBLE_EXES=(
            "$OUTPUT_DIR/main.exe"
        )
        
        for exe in "${POSSIBLE_EXES[@]}"; do
            if [ -f "$exe" ]; then
                log_info "找到可执行文件: $exe"
                mv "$exe" "$EXE_FILE"
                break
            fi
        done
    fi
    
    if [ -f "$EXE_FILE" ]; then
        log_success "可执行文件构建成功: $EXE_FILE"
        
        # 显示文件信息
        ls -lh "$EXE_FILE"
        
        # 测试可执行文件
        log_info "测试可执行文件..."
        if wine "$EXE_FILE" --help 2>/dev/null | grep -q "Rime"; then
            log_success "可执行文件测试通过"
        else
            log_warning "可执行文件测试可能有问题，但文件已生成"
        fi
        
        # 验证关键文件是否被包含
        log_info "验证打包内容..."
        wine "$EXE_FILE" --version 2>/dev/null || log_warning "版本检查可能有问题"
    else
        log_error "可执行文件构建失败"
        # 显示构建目录内容以帮助调试
        log_info "构建目录内容:"
        ls -la "$OUTPUT_DIR/" 2>/dev/null || echo "输出目录不存在"
        ls -la build/ 2>/dev/null || echo "构建目录不存在"
        exit 1
    fi
}

# 清理临时文件
cleanup() {
    log_info "清理临时文件..."
    
    # 删除临时文件
    rm -rf build
    rm -f *.spec
    rm -f version_info.txt
    rm -f python-*.zip
    rm -f python-*.exe
    
    log_success "清理完成"
}

# 打包发布文件
package_release() {
    log_info "打包发布文件..."
    
    RELEASE_DIR="release"
    rm -rf "$RELEASE_DIR"
    mkdir -p "$RELEASE_DIR"
    
    # 复制可执行文件
    cp "$OUTPUT_DIR/${PROJECT_NAME}.exe" "$RELEASE_DIR/"
    
    # 复制示例数据文件（如果存在）
    if [ -d "pinyin_data" ]; then
        cp -r pinyin_data "$RELEASE_DIR/"
    fi
    
    # 创建README
    cat > "$RELEASE_DIR/README.txt" << EOF
Rime词典拼音修正工具 v1.0
===============================

使用说明:
1. 将需要处理的词典文件放在与可执行文件同目录
2. 修改程序中的input_dir和output_dir变量指向正确的路径
3. 运行 ${PROJECT_NAME}.exe

注意事项:
- 支持普通词表和Rime userdb格式
- 自动识别用户词典格式
- 保留辅助码和后缀
- 支持批量处理目录

构建信息:
- 构建时间: $(date)
- 构建平台: Debian 12 (交叉编译)
- 目标平台: Windows x64
- Python版本: $PYTHON_VERSION
EOF
    
    # 创建压缩包
    cd "$RELEASE_DIR"
    zip -r "../${PROJECT_NAME}-windows-x64.zip" .
    cd ..
    
    log_success "发布包创建完成: ${PROJECT_NAME}-windows-x64.zip"
}

# 主函数
main() {
    log_info "开始构建 $PROJECT_NAME for Windows x64"
    log_info "构建平台: Debian 12"
    log_info "目标平台: Windows x64"
    log_info "=========================================="
    
    # 检查是否在正确的目录
    if [ ! -f "$MAIN_SCRIPT" ]; then
        log_error "请在包含 '$MAIN_SCRIPT' 的目录中运行此脚本"
        exit 1
    fi
    
    # 执行构建步骤
    install_system_deps
    init_wine
    install_python_wine
    install_python_deps
    prepare_build
    create_spec_file
    create_version_info
    build_executable
    package_release
    cleanup
    
    log_success "=========================================="
    log_success "构建完成！"
    log_success "可执行文件: $OUTPUT_DIR/${PROJECT_NAME}.exe"
    log_success "发布包: ${PROJECT_NAME}-windows-x64.zip"
    log_success "=========================================="
}

# 错误处理
trap 'log_error "构建过程中发生错误，退出中..."; exit 1' ERR

# 运行主函数
main "$@"
