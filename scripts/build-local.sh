#!/bin/bash
# -*- coding: utf-8 -*-
# 本地测试构建脚本 - 不使用Wine，用于测试PyInstaller配置

set -e

# 颜色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

PROJECT_NAME="rime-dict-processor"
MAIN_SCRIPT="src/main.py"
MAIN_SCRIPT="main.py"
OUTPUT_DIR="dist"

# 检查Python和依赖
log_info "检查Python环境..."
python3 --version
pip3 list | grep -E "(pypinyin|tqdm|pyinstaller)" || {
    log_info "安装依赖包..."
    pip3 install pypinyin tqdm pyinstaller
}

# 清理旧文件
log_info "清理旧构建文件..."
rm -rf "$OUTPUT_DIR" build *.spec

# 创建spec文件
log_info "创建PyInstaller spec文件..."
cat > "${PROJECT_NAME}.spec" << EOF
# -*- mode: python ; coding: utf-8 -*-

import os
import sys
from PyInstaller.utils.hooks import collect_data_files

datas = []
datas += collect_data_files('pypinyin')
datas += collect_data_files('tqdm')

if os.path.exists('data/pinyin_data'):
    datas += [('data/pinyin_data', 'pinyin_data')]

hiddenimports = [
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
    'importlib',
    'importlib.util',
]

a = Analysis(
    ['$MAIN_SCRIPT'],
    pathex=['.'],
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
    upx=False,
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

# 构建
log_info "开始构建..."
pyinstaller --clean --noconfirm "${PROJECT_NAME}.spec"

# 检查结果
if [ -f "$OUTPUT_DIR/$PROJECT_NAME" ]; then
    log_success "构建成功: $OUTPUT_DIR/$PROJECT_NAME"
    ls -lh "$OUTPUT_DIR/$PROJECT_NAME"
    
    # 测试
    log_info "测试可执行文件..."
    "./$OUTPUT_DIR/$PROJECT_NAME" --help
else
    echo "构建失败"
    exit 1
fi

log_success "本地测试构建完成"
