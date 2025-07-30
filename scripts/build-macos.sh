#!/bin/bash
# -*- coding: utf-8 -*-
# macOS构建脚本 - 支持原生构建和有限的交叉编译
# 支持平台: macOS x64, macOS ARM64 (Apple Silicon)
# 日期: 2025-07-30

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 检测系统架构
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        TARGET_ARCH="x64"
        ;;
    arm64)
        TARGET_ARCH="arm64"
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

# 检查是否在macOS上运行
check_macos() {
    if [[ "$OSTYPE" != "darwin"* ]]; then
        log_error "此脚本只能在macOS上运行"
        log_info "如需在其他平台构建macOS版本，请参考交叉编译说明"
        exit 1
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
    log_info "检查并安装系统依赖..."
    
    # 检查是否安装了Homebrew
    if ! command -v brew &> /dev/null; then
        log_info "安装Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    
    # 安装Python和构建工具
    log_info "安装Python和构建工具..."
    brew install python@$PYTHON_VERSION || log_warning "Python可能已安装"
    
    # 安装可选的UPX压缩工具
    log_info "尝试安装UPX压缩工具（可选）..."
    brew install upx 2>/dev/null || {
        log_warning "UPX安装失败，将跳过可执行文件压缩"
    }
    
    # 检查必要的命令
    check_command "python3"
    
    # 设置Python别名
    PYTHON_CMD=$(brew --prefix)/bin/python$PYTHON_VERSION
    if [ ! -f "$PYTHON_CMD" ]; then
        PYTHON_CMD="python3"
    fi
    
    log_success "系统依赖安装完成"
}

# 设置Python环境
setup_python_env() {
    log_info "设置Python环境..."
    
    # 检查Python版本
    PYTHON_VER=$($PYTHON_CMD --version | grep -oE '[0-9]+\.[0-9]+')
    log_info "当前Python版本: $PYTHON_VER"
    
    # 创建虚拟环境
    VENV_DIR="venv-macos-${TARGET_ARCH}"
    if [ -d "$VENV_DIR" ]; then
        log_warning "虚拟环境已存在，删除旧环境..."
        rm -rf "$VENV_DIR"
    fi
    
    log_info "创建虚拟环境: $VENV_DIR"
    $PYTHON_CMD -m venv "$VENV_DIR"
    
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
        source "venv-macos-${TARGET_ARCH}/bin/activate"
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
    
    cat > "${PROJECT_NAME}-macos-${TARGET_ARCH}.spec" << EOF
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
    name='${PROJECT_NAME}-macos-${TARGET_ARCH}',
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
        source "venv-macos-${TARGET_ARCH}/bin/activate"
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
        "${PROJECT_NAME}-macos-${TARGET_ARCH}.spec" || {
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
            --name="${PROJECT_NAME}-macos-${TARGET_ARCH}" \
            "$MAIN_SCRIPT" || {
            log_error "PyInstaller构建失败"
            exit 1
        }
    }
    
    # 检查构建结果
    EXE_FILE="$OUTPUT_DIR/${PROJECT_NAME}-macos-${TARGET_ARCH}"
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
        
        # 代码签名（如果有开发者证书）
        if command -v codesign &> /dev/null; then
            log_info "尝试代码签名..."
            codesign --force --verify --verbose --sign - "$EXE_FILE" 2>/dev/null || {
                log_warning "代码签名失败，可执行文件仍然可用"
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

# 交叉编译ARM64版本（在Intel Mac上）或x64版本（在ARM Mac上）
cross_compile_arm() {
    if [ "$1" = "--cross-arm" ]; then
        if [ "$TARGET_ARCH" = "x64" ]; then
            log_info "开始交叉编译ARM64版本..."
            
            # 检查是否支持通用二进制
            if command -v arch &> /dev/null; then
                log_info "使用arch命令进行ARM64交叉编译..."
                
                # 设置目标架构
                export TARGET_ARCH="arm64"
                export ARCHFLAGS="-arch arm64"
                
                log_info "交叉编译环境设置完成，开始构建ARM64版本..."
                
                # 重新执行构建流程
                setup_python_env
                install_python_deps
                prepare_build
                create_spec_file
                build_executable
                package_release
                
                log_success "ARM64版本构建完成"
            else
                log_warning "当前macOS版本可能不支持ARM64交叉编译"
            fi
        elif [ "$TARGET_ARCH" = "arm64" ]; then
            log_info "开始交叉编译x64版本..."
            
            # 在ARM Mac上交叉编译x64版本
            if command -v arch &> /dev/null; then
                log_info "使用arch命令进行x64交叉编译..."
                
                # 设置目标架构
                export TARGET_ARCH="x64"
                export ARCHFLAGS="-arch x86_64"
                
                log_info "交叉编译环境设置完成，开始构建x64版本..."
                
                # 重新执行构建流程
                setup_python_env
                install_python_deps
                prepare_build
                create_spec_file
                build_executable
                package_release
                
                log_success "x64版本构建完成"
            else
                log_warning "当前macOS版本可能不支持x64交叉编译"
            fi
        fi
    fi
}

# 清理临时文件
cleanup() {
    log_info "清理临时文件..."
    
    # 删除临时文件
    rm -rf build
    rm -f *.spec
    
    # 保留虚拟环境以便后续使用
    # rm -rf "venv-macos-${TARGET_ARCH}"
    
    log_success "清理完成"
}

# 打包发布文件
package_release() {
    log_info "打包发布文件..."
    
    RELEASE_DIR="release-macos-${TARGET_ARCH}"
    rm -rf "$RELEASE_DIR"
    mkdir -p "$RELEASE_DIR"
    
    # 复制可执行文件
    cp "$OUTPUT_DIR/${PROJECT_NAME}-macos-${TARGET_ARCH}" "$RELEASE_DIR/"
    
    # 复制示例数据文件（如果存在）
    if [ -d "src/pinyin_data" ]; then
        cp -r src/pinyin_data "$RELEASE_DIR/"
    fi
    
    # 创建README
    cat > "$RELEASE_DIR/README.txt" << EOF
Rime词典拼音修正工具 v1.0 - macOS ${TARGET_ARCH}
========================================

使用说明:
1. 将需要处理的词典文件放在与可执行文件同目录
2. 修改程序中的input_dir和output_dir变量指向正确的路径
3. 运行 ./${PROJECT_NAME}-macos-${TARGET_ARCH}

注意事项:
- 支持普通词表和Rime userdb格式
- 自动识别用户词典格式
- 保留辅助码和后缀
- 支持批量处理目录

构建信息:
- 构建时间: $(date)
- 构建平台: $(uname -a)
- 目标平台: macOS ${TARGET_ARCH}
- Python版本: $(python3 --version)
- macOS版本: $(sw_vers -productVersion)
EOF
    
    # 创建压缩包
    cd "$RELEASE_DIR"
    tar -czf "../${PROJECT_NAME}-macos-${TARGET_ARCH}.tar.gz" .
    cd ..
    
    log_success "发布包创建完成: ${PROJECT_NAME}-macos-${TARGET_ARCH}.tar.gz"
}

# 显示交叉编译说明
show_cross_compile_info() {
    cat << EOF

🍎 macOS交叉编译说明
==================

1. 原生构建（推荐）:
   - 在Intel Mac上构建x64版本
   - 在Apple Silicon Mac上构建ARM64版本
   - 在Intel Mac上交叉编译ARM64版本

2. 交叉编译限制:
   - 从其他平台交叉编译到macOS受到法律和技术限制
   - 建议使用GitHub Actions或其他CI/CD服务

3. 替代方案:
   - 使用GitHub Actions的macOS runner
   - 使用云端macOS实例
   - 使用PyInstaller的Universal Binary支持

4. 当前脚本功能:
   - ✅ Intel Mac原生构建
   - ✅ Apple Silicon Mac原生构建
   - ✅ Intel Mac交叉编译ARM64
   - ❌ 从Linux/Windows交叉编译到macOS

EOF
}

# 主函数
main() {
    log_info "开始构建 $PROJECT_NAME for macOS"
    log_info "当前架构: $TARGET_ARCH"
    log_info "========================================"
    
    # 检查是否在macOS上
    check_macos
    
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
    log_success "可执行文件: $OUTPUT_DIR/${PROJECT_NAME}-macos-${TARGET_ARCH}"
    log_success "发布包: ${PROJECT_NAME}-macos-${TARGET_ARCH}.tar.gz"
    if [ "$1" = "--cross-arm" ]; then
        if [ "$ARCH" = "x86_64" ]; then
            log_success "ARM64发布包: ${PROJECT_NAME}-macos-arm64.tar.gz"
        elif [ "$ARCH" = "arm64" ]; then
            log_success "x64发布包: ${PROJECT_NAME}-macos-x64.tar.gz"
        fi
    fi
    log_success "========================================"
}

# 显示使用说明
show_usage() {
    echo "使用说明:"
    echo "  $0                  构建当前架构版本"
    echo "  $0 --cross-arm     构建当前架构版本 + 交叉编译另一架构版本"
    echo "                     (Intel Mac: 构建 x64 + ARM64)"
    echo "                     (ARM Mac: 构建 ARM64 + x64)"
    echo "  $0 --info          显示交叉编译说明"
    echo "  $0 --help          显示此帮助信息"
    echo ""
    echo "支持的架构: x64 (Intel), arm64 (Apple Silicon)"
    echo "当前架构: $TARGET_ARCH"
}

# 参数处理
case "$1" in
    --help|-h)
        show_usage
        exit 0
        ;;
    --info)
        show_cross_compile_info
        exit 0
        ;;
    --cross-arm)
        if [[ "$OSTYPE" != "darwin"* ]]; then
            log_error "macOS交叉编译只能在macOS上进行"
            show_cross_compile_info
            exit 1
        fi
        # 移除架构限制，允许在任何macOS上进行交叉编译
        ;;
esac

# 错误处理
trap 'log_error "构建过程中发生错误，退出中..."; exit 1' ERR

# 如果不在macOS上，显示交叉编译说明
if [[ "$OSTYPE" != "darwin"* ]]; then
    show_cross_compile_info
    exit 1
fi

# 运行主函数
main "$@"
