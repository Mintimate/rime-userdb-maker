#!/bin/bash
# 项目构建状态检查脚本

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "🔍 检查项目构建状态..."
echo

# 检查必要文件
echo "📁 检查项目结构..."
required_files=(
    "src/main.py"
    "src/rime_processor_embedded.py"
    "scripts/build.sh"
    "scripts/build-local.sh"
    "requirements.txt"
    "README.md"
    ".github/workflows/build.yml"
)

missing_files=()
for file in "${required_files[@]}"; do
    if [[ -f "$file" ]]; then
        echo -e "  ✅ $file"
    else
        echo -e "  ❌ $file"
        missing_files+=("$file")
    fi
done

if [[ ${#missing_files[@]} -gt 0 ]]; then
    echo -e "\n${RED}❌ 缺少必要文件:${NC}"
    for file in "${missing_files[@]}"; do
        echo "   - $file"
    done
    exit 1
fi

# 检查Python依赖
echo -e "\n🐍 检查Python依赖..."
if command -v python3 &> /dev/null; then
    echo "  ✅ Python3 已安装"
    
    # 检查必要的包
    packages=("pypinyin" "tqdm")
    for package in "${packages[@]}"; do
        if python3 -c "import $package" 2>/dev/null; then
            echo "  ✅ $package 已安装"
        else
            echo -e "  ${YELLOW}⚠️ $package 未安装${NC}"
            echo "    运行: pip install -r requirements.txt"
        fi
    done
else
    echo -e "  ${RED}❌ Python3 未安装${NC}"
fi

# 检查构建脚本权限
echo -e "\n🔐 检查脚本权限..."
scripts=("scripts/build.sh" "scripts/build-local.sh")
for script in "${scripts[@]}"; do
    if [[ -x "$script" ]]; then
        echo "  ✅ $script 可执行"
    else
        echo -e "  ${YELLOW}⚠️ $script 不可执行${NC}"
        echo "    运行: chmod +x $script"
    fi
done

# 检查构建输出
echo -e "\n📦 检查构建状态..."
if [[ -f "dist/rime-dict-processor.exe" ]]; then
    size=$(ls -lh dist/rime-dict-processor.exe | awk '{print $5}')
    echo "  ✅ Windows可执行文件已存在 ($size)"
else
    echo -e "  ${YELLOW}⚠️ Windows可执行文件不存在${NC}"
    echo "    运行: ./scripts/build.sh"
fi

# 测试基本功能
echo -e "\n🧪 测试基本功能..."
if python3 -c "
import sys
sys.path.insert(0, 'src')
try:
    from rime_processor_embedded import normal_line
    result = normal_line(['测试'])
    print(f'  ✅ 处理功能正常: {result}')
except Exception as e:
    print(f'  ❌ 处理功能错误: {e}')
    sys.exit(1)
" 2>/dev/null; then
    echo "  ✅ 核心功能测试通过"
else
    echo -e "  ${RED}❌ 核心功能测试失败${NC}"
fi

echo -e "\n${GREEN}🎉 项目状态检查完成！${NC}"
echo
echo "📋 快速命令:"
echo "  🏗️  本地构建: ./scripts/build-local.sh"
echo "  🏗️  交叉编译: ./scripts/build.sh"
echo "  🧪 运行测试: python -m pytest tests/"
echo "  📚 查看帮助: python src/main.py --help"
