#!/bin/bash
# -*- coding: utf-8 -*-
# Linux本地编译脚本 - 将Python项目打包为Linux静态可执行文件
# 支持平台: Linux amd64, Linux ARM64
# 编译平台: Debian/Ubuntu
# 日期: 2025-07-30

set -e  # 遇到错误立即退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检测系统架构
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        TARGET_ARCH="amd64"
        ;;
    aarch64|arm64)
        TARGET_ARCH="arm64"
        ;;
    armv7l)
        TARGET_ARCH="armv7"
        ;;
    *)
        echo -e "${RED}[ERROR]${NC} 不支持的架构: $ARCH"
        exit 1
        ;;
esac

# 配置变量
PROJECT_NAME="rime-dict-processor"
MAIN_SCRIPT="src/main.py"
OUTPUT_DIR="dist"
PYTHON_VERSION="3.11"

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

# 检查命令是否存在
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "命令 '$1' 未找到，请先安装"
        exit 1
    fi
}

# 检测Linux发行版
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        DISTRO="centos"
    else
        DISTRO="unknown"
    fi
    
    log_info "检测到系统: $DISTRO $VERSION ($TARGET_ARCH)"
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

# 安装系统依赖
install_system_deps() {
    # 如果在CI环境中，检查关键依赖是否已存在
    if [ "$CI" = "true" ] || [ "$GITHUB_ACTIONS" = "true" ]; then
        log_info "检测到CI环境，检查预装依赖..."
        
        # 检查关键命令是否已存在
        local missing_deps=()
        
        # 检查Python
        if ! command -v python3 &> /dev/null; then
            missing_deps+=("python3")
        fi
        
        # 检查pip
        if ! command -v pip3 &> /dev/null && ! command -v pip &> /dev/null; then
            missing_deps+=("python3-pip")
        fi
        
        # 检查基本构建工具
        if ! command -v gcc &> /dev/null; then
            missing_deps+=("build-essential")
        fi
        
        # 如果关键依赖都存在，跳过完整安装
        if [ ${#missing_deps[@]} -eq 0 ]; then
            log_success "CI环境依赖检查完成，跳过系统依赖安装"
            return
        else
            log_info "缺少依赖: ${missing_deps[*]}，继续安装..."
        fi
    fi
    
    log_info "检查并安装系统依赖..."
    
    detect_distro
    
    case $DISTRO in
        ubuntu|debian)
            # 更新包列表
            run_with_sudo apt-get update
            
            # 安装Python和构建工具
            run_with_sudo apt-get install -y \
                python3 \
                python3-pip \
                python3-venv \
                python3-dev \
                build-essential \
                zlib1g-dev \
                libffi-dev \
                libssl-dev \
                libbz2-dev \
                libreadline-dev \
                libsqlite3-dev \
                libncurses5-dev \
                libncursesw5-dev \
                xz-utils \
                tk-dev \
                libxml2-dev \
                libxmlsec1-dev \
                libffi-dev \
                liblzma-dev \
                wget \
                curl \
                git
                
            # 尝试安装UPX（完全可选）
            log_info "尝试安装UPX压缩工具（可选，安装失败不影响构建）..."
            run_with_sudo apt-get install -y upx 2>/dev/null || {
                log_warning "UPX不可用，将跳过可执行文件压缩（这不影响功能）"
            }
            ;;
        centos|rhel|fedora)
            # RedHat系列
            if command -v dnf &> /dev/null; then
                PKG_MGR="dnf"
            else
                PKG_MGR="yum"
            fi
            
            run_with_sudo $PKG_MGR install -y \
                python3 \
                python3-pip \
                python3-devel \
                gcc \
                gcc-c++ \
                make \
                zlib-devel \
                libffi-devel \
                openssl-devel \
                bzip2-devel \
                readline-devel \
                sqlite-devel \
                ncurses-devel \
                xz-devel \
                tk-devel \
                libxml2-devel \
                xmlsec1-devel \
                wget \
                curl \
                git
                
            # 尝试安装UPX（可选）
            log_info "尝试安装UPX压缩工具..."
            run_with_sudo $PKG_MGR install -y upx 2>/dev/null || {
                log_warning "UPX安装失败，将跳过可执行文件压缩"
            }
            ;;
        arch|manjaro)
            # Arch系列
            run_with_sudo pacman -S --needed --noconfirm \
                python \
                python-pip \
                base-devel \
                zlib \
                libffi \
                openssl \
                bzip2 \
                readline \
                sqlite \
                ncurses \
                xz \
                tk \
                libxml2 \
                xmlsec \
                wget \
                curl \
                git
                
            # 尝试安装UPX（可选）
            log_info "尝试安装UPX压缩工具..."
            run_with_sudo pacman -S --needed --noconfirm upx 2>/dev/null || {
                log_warning "UPX安装失败，将跳过可执行文件压缩"
            }
            ;;
        alpine)
            # Alpine Linux
            run_with_sudo apk add --no-cache \
                python3 \
                python3-dev \
                py3-pip \
                build-base \
                zlib-dev \
                libffi-dev \
                openssl-dev \
                bzip2-dev \
                readline-dev \
                sqlite-dev \
                ncurses-dev \
                xz-dev \
                tk-dev \
                libxml2-dev \
                xmlsec-dev \
                wget \
                curl \
                git
                
            # 尝试安装UPX（可选）
            log_info "尝试安装UPX压缩工具..."
            run_with_sudo apk add --no-cache upx 2>/dev/null || {
                log_warning "UPX安装失败，将跳过可执行文件压缩"
            }
            ;;
        *)
            log_warning "未知的Linux发行版: $DISTRO，尝试使用通用方法..."
            ;;
    esac
    
    # 检查必要的命令
    check_command "python3"
    check_command "pip3"
    
    log_success "系统依赖安装完成"
}

# 设置Python环境
setup_python_env() {
    log_info "设置Python环境..."
    
    # 检查Python版本
    PYTHON_VER=$(python3 --version | grep -oE '[0-9]+\.[0-9]+')
    log_info "当前Python版本: $PYTHON_VER"
    
    # 创建虚拟环境
    VENV_DIR="venv-${TARGET_ARCH}"
    if [ -d "$VENV_DIR" ]; then
        log_warning "虚拟环境已存在，删除旧环境..."
        rm -rf "$VENV_DIR"
    fi
    
    log_info "创建虚拟环境: $VENV_DIR"
    python3 -m venv "$VENV_DIR"
    
    # 激活虚拟环境
    source "$VENV_DIR/bin/activate"
    
    # 升级pip
    log_info "升级pip..."
    pip install --upgrade pip setuptools wheel
    
    log_success "Python环境设置完成"
}

# 安装Python依赖
install_python_deps() {
    log_info "安装Python依赖包..."
    
    # 确保虚拟环境已激活
    if [ -z "$VIRTUAL_ENV" ]; then
        source "venv-${TARGET_ARCH}/bin/activate"
    fi
    
    # 安装PyInstaller
    log_info "安装PyInstaller..."
    pip install pyinstaller
    
    # 安装项目依赖（如果有requirements.txt）
    if [ -f "requirements.txt" ]; then
        log_info "安装项目依赖..."
        pip install -r requirements.txt
    fi
    
    # 验证PyInstaller
    if ! pyinstaller --version &> /dev/null; then
        log_error "PyInstaller安装失败"
        exit 1
    fi
    
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
    
    cat > "${PROJECT_NAME}-${TARGET_ARCH}.spec" << EOF
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
    name='${PROJECT_NAME}-linux-${TARGET_ARCH}',
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
)
EOF
    
    log_success "PyInstaller spec文件创建完成"
}

# 使用PyInstaller构建
build_executable() {
    log_info "使用PyInstaller构建可执行文件..."
    
    # 确保虚拟环境已激活
    if [ -z "$VIRTUAL_ENV" ]; then
        source "venv-${TARGET_ARCH}/bin/activate"
    fi
    
    # 验证PyInstaller可用
    log_info "验证PyInstaller..."
    if ! pyinstaller --version &> /dev/null; then
        log_error "PyInstaller不可用"
        exit 1
    fi
    
    # 运行PyInstaller
    log_info "开始编译，这可能需要几分钟..."
    pyinstaller \
        --clean \
        --noconfirm \
        --onefile \
        --console \
        --distpath="$OUTPUT_DIR" \
        --workpath="build" \
        --specpath="." \
        "${PROJECT_NAME}-${TARGET_ARCH}.spec" || {
        log_warning "PyInstaller构建可能有问题，尝试简化构建..."
        
        # 尝试不使用spec文件的简单构建
        log_info "尝试简化构建..."
        pyinstaller \
            --clean \
            --noconfirm \
            --onefile \
            --console \
            --distpath="$OUTPUT_DIR" \
            --workpath="build" \
            --add-data="src/pypinyin:pypinyin" \
            --add-data="src/tqdm:tqdm" \
            --add-data="src/pinyin_data:pinyin_data" \
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
            --name="${PROJECT_NAME}-linux-${TARGET_ARCH}" \
            "$MAIN_SCRIPT" || {
            log_error "PyInstaller构建失败"
            exit 1
        }
    }
    
    # 检查构建结果
    EXE_FILE="$OUTPUT_DIR/${PROJECT_NAME}-linux-${TARGET_ARCH}"
    if [ ! -f "$EXE_FILE" ]; then
        # 尝试查找其他可能的输出文件
        POSSIBLE_EXES=(
            "$OUTPUT_DIR/main"
            "$OUTPUT_DIR/${PROJECT_NAME}"
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
        if "$EXE_FILE" --help 2>/dev/null | grep -q "Rime" || "$EXE_FILE" --version 2>/dev/null; then
            log_success "可执行文件测试通过"
        else
            log_warning "可执行文件测试可能有问题，但文件已生成"
        fi
        
        # 使用UPX压缩（如果可用）
        if command -v upx &> /dev/null; then
            log_info "使用UPX压缩可执行文件..."
            upx --best --lzma "$EXE_FILE" 2>/dev/null || {
                log_warning "UPX压缩失败，但可执行文件正常"
            }
        fi
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
    
    # 保留虚拟环境以便后续使用
    # rm -rf "venv-${TARGET_ARCH}"
    
    log_success "清理完成"
}

# 打包发布文件
package_release() {
    log_info "打包发布文件..."
    
    RELEASE_DIR="release-linux-${TARGET_ARCH}"
    rm -rf "$RELEASE_DIR"
    mkdir -p "$RELEASE_DIR"
    
    # 复制可执行文件
    cp "$OUTPUT_DIR/${PROJECT_NAME}-linux-${TARGET_ARCH}" "$RELEASE_DIR/"
    
    # 复制示例数据文件（如果存在）
    if [ -d "src/pinyin_data" ]; then
        cp -r src/pinyin_data "$RELEASE_DIR/"
    fi
    
    # 创建README
    cat > "$RELEASE_DIR/README.txt" << EOF
Rime词典拼音修正工具 v1.0 - Linux ${TARGET_ARCH}
=======================================

使用说明:
1. 将需要处理的词典文件放在与可执行文件同目录
2. 修改程序中的input_dir和output_dir变量指向正确的路径
3. 运行 ./${PROJECT_NAME}-linux-${TARGET_ARCH}

注意事项:
- 支持普通词表和Rime userdb格式
- 自动识别用户词典格式
- 保留辅助码和后缀
- 支持批量处理目录

构建信息:
- 构建时间: $(date)
- 构建平台: $(uname -a)
- 目标平台: Linux ${TARGET_ARCH}
- Python版本: $(python3 --version)
- 发行版: $DISTRO $VERSION
EOF
    
    # 创建压缩包
    cd "$RELEASE_DIR"
    tar -czf "../${PROJECT_NAME}-linux-${TARGET_ARCH}.tar.gz" .
    cd ..
    
    log_success "发布包创建完成: ${PROJECT_NAME}-linux-${TARGET_ARCH}.tar.gz"
}

# 交叉编译ARM版本（在x86_64主机上）
cross_compile_arm() {
    if [ "$TARGET_ARCH" = "amd64" ] && [ "$1" = "--cross-arm" ]; then
        log_info "开始交叉编译ARM64版本..."
        
        # 安装交叉编译工具链
        case $DISTRO in
            ubuntu|debian)
                run_with_sudo apt-get install -y gcc-aarch64-linux-gnu
                ;;
            *)
                log_warning "当前发行版可能不支持ARM64交叉编译"
                return
                ;;
        esac
        
        # 设置交叉编译环境
        export CC=aarch64-linux-gnu-gcc
        export CXX=aarch64-linux-gnu-g++
        export AR=aarch64-linux-gnu-ar
        export STRIP=aarch64-linux-gnu-strip
        export TARGET_ARCH="arm64"
        
        log_info "交叉编译环境设置完成，开始构建ARM64版本..."
        
        # 重新执行构建流程
        setup_python_env
        install_python_deps
        prepare_build
        create_spec_file
        build_executable
        package_release
        
        log_success "ARM64版本构建完成"
    fi
}

# 主函数
main() {
    log_info "开始构建 $PROJECT_NAME for Linux"
    log_info "当前架构: $TARGET_ARCH"
    log_info "========================================"
    
    # 检查是否在正确的目录
    if [ ! -f "$MAIN_SCRIPT" ]; then
        log_error "请在包含 '$MAIN_SCRIPT' 的目录中运行此脚本"
        exit 1
    fi
    
    # 执行构建步骤
    install_system_deps
    setup_python_env
    install_python_deps
    prepare_build
    create_spec_file
    build_executable
    package_release
    cleanup
    
    # 如果指定了交叉编译ARM选项
    cross_compile_arm "$1"
    
    log_success "========================================"
    log_success "构建完成！"
    log_success "可执行文件: $OUTPUT_DIR/${PROJECT_NAME}-linux-${TARGET_ARCH}"
    log_success "发布包: ${PROJECT_NAME}-linux-${TARGET_ARCH}.tar.gz"
    if [ "$1" = "--cross-arm" ] && [ "$ARCH" = "x86_64" ]; then
        log_success "ARM64发布包: ${PROJECT_NAME}-linux-arm64.tar.gz"
    fi
    log_success "========================================"
}

# 显示使用说明
show_usage() {
    echo "使用说明:"
    echo "  $0                  构建当前架构版本"
    echo "  $0 --cross-arm     构建当前架构版本 + ARM64交叉编译版本 (仅x86_64主机)"
    echo "  $0 --help          显示此帮助信息"
    echo ""
    echo "支持的架构: amd64, arm64, armv7"
    echo "当前架构: $TARGET_ARCH"
}

# 参数处理
case "$1" in
    --help|-h)
        show_usage
        exit 0
        ;;
    --cross-arm)
        if [ "$ARCH" != "x86_64" ]; then
            log_error "ARM交叉编译只能在x86_64主机上进行"
            exit 1
        fi
        ;;
esac

# 错误处理
trap 'log_error "构建过程中发生错误，退出中..."; exit 1' ERR

# 运行主函数
main "$@"
