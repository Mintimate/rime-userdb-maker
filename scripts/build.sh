#!/bin/bash
# -*- coding: utf-8 -*-
# 通用构建脚本 - 支持多平台构建
# 支持平台: Linux (amd64, ARM64), Windows (交叉编译), macOS (原生)
# 日期: 2025-07-30

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 项目信息
PROJECT_NAME="rime-dict-processor"
VERSION="1.0.0"

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

# 显示使用说明
show_usage() {
    echo "Rime词典拼音修正工具 - 通用构建脚本 v$VERSION"
    echo "================================================"
    echo ""
    echo "使用说明:"
    echo "  $0 linux              构建Linux版本 (当前架构)"
    echo "  $0 linux --cross-arm  构建Linux版本 + ARM64交叉编译"
    echo "  $0 windows            构建Windows版本 (Wine交叉编译)"
    echo "  $0 macos              构建macOS版本 (仅macOS系统)"
    echo "  $0 macos --cross-arm  构建macOS版本 + 交叉编译另一架构版本"
    echo "                        (Intel Mac: x64 + ARM64, ARM Mac: ARM64 + x64)"
    echo "  $0 all                构建所有平台版本"
    echo "  $0 clean              清理所有构建文件"
    echo "  $0 --help             显示此帮助信息"
    echo ""
    echo "构建输出:"
    echo "  dist/                 可执行文件目录"
    echo "  *.tar.gz             Linux/macOS发布包"
    echo "  *.zip                Windows发布包"
    echo ""
    echo "当前系统: $(uname -s) $(uname -m)"
}

# 检查脚本是否存在
check_script() {
    local script="$1"
    if [ ! -f "$script" ]; then
        log_error "构建脚本不存在: $script"
        exit 1
    fi
    
    if [ ! -x "$script" ]; then
        log_error "构建脚本不可执行: $script"
        exit 1
    fi
}

# 构建Linux版本
build_linux() {
    log_info "构建Linux版本..."
    
    local script="scripts/build-linux.sh"
    check_script "$script"
    
    if [ "$1" = "--cross-arm" ]; then
        log_info "启用ARM64交叉编译..."
        ./"$script" --cross-arm
    else
        ./"$script"
    fi
    
    log_success "Linux版本构建完成"
}

# 构建macOS版本
build_macos() {
    log_info "构建macOS版本..."
    
    local script="scripts/build-macos.sh"
    check_script "$script"
    
    if [ "$1" = "--cross-arm" ]; then
        log_info "启用ARM64交叉编译..."
        ./"$script" --cross-arm
    else
        ./"$script"
    fi
    
    log_success "macOS版本构建完成"
}

# 构建Windows版本
build_windows() {
    log_info "构建Windows版本..."
    
    local script="scripts/build-windows.sh"
    check_script "$script"
    
    ./"$script"
    
    log_success "Windows版本构建完成"
}

# 构建所有版本
build_all() {
    log_info "构建所有平台版本..."
    log_info "这可能需要较长时间，请耐心等待..."
    echo ""
    
    # 构建Linux版本（包括ARM交叉编译）
    if [ "$(uname -m)" = "x86_64" ]; then
        log_info "=== 构建Linux版本（包括ARM64交叉编译）==="
        build_linux --cross-arm
    else
        log_info "=== 构建Linux版本（当前架构）==="
        build_linux
    fi
    
    echo ""
    
    # 构建macOS版本（如果在macOS上）
    if [[ "$OSTYPE" == "darwin"* ]]; then
        log_info "=== 构建macOS版本 ==="
        if [ "$(uname -m)" = "x86_64" ]; then
            build_macos --cross-arm
        else
            build_macos
        fi
        echo ""
    else
        log_warning "跳过macOS构建（需要在macOS系统上运行）"
        echo ""
    fi
    
    # 构建Windows版本
    log_info "=== 构建Windows版本 ==="
    build_windows
    
    echo ""
    log_success "所有平台版本构建完成！"
    
    # 显示构建结果
    show_build_results
}

# 清理构建文件
clean_build() {
    log_info "清理构建文件..."
    
    # 清理目录和文件
    rm -rf dist/
    rm -rf build/
    rm -rf release*/
    rm -rf venv-*/
    rm -f *.spec
    rm -f *.tar.gz
    rm -f *.zip
    rm -f version_info.txt
    rm -f python-*.exe
    rm -f python-*.zip
    
    log_success "构建文件清理完成"
}

# 显示构建结果
show_build_results() {
    log_info "构建结果摘要:"
    echo "================================================"
    
    # 可执行文件
    if [ -d "dist" ]; then
        echo "可执行文件:"
        ls -lh dist/ 2>/dev/null | grep -v "^total" || echo "  无"
    fi
    
    echo ""
    
    # 发布包
    echo "发布包:"
    ls -lh *.tar.gz *.zip 2>/dev/null || echo "  无"
    
    echo "================================================"
}

# 验证环境
check_environment() {
    # 检查是否在项目根目录
    if [ ! -f "src/main.py" ]; then
        log_error "请在项目根目录运行此脚本"
        log_error "当前目录: $(pwd)"
        log_error "应包含: src/main.py"
        exit 1
    fi
    
    # 检查构建脚本
    if [ ! -d "scripts" ]; then
        log_error "构建脚本目录不存在: scripts/"
        exit 1
    fi
}

# 主函数
main() {
    # 验证环境
    check_environment
    
    # 处理参数
    case "$1" in
        "linux")
            shift
            build_linux "$@"
            ;;
        "windows")
            build_windows
            ;;
        "macos")
            shift
            build_macos "$@"
            ;;
        "all")
            build_all
            ;;
        "clean")
            clean_build
            ;;
        "--help"|"-h"|"help"|"")
            show_usage
            exit 0
            ;;
        *)
            log_error "未知的命令: $1"
            echo ""
            show_usage
            exit 1
            ;;
    esac
    
    # 显示最终结果
    if [ "$1" != "clean" ]; then
        echo ""
        show_build_results
    fi
}

# 错误处理
trap 'log_error "构建过程中发生错误"; exit 1' ERR

# 运行主函数
main "$@"
