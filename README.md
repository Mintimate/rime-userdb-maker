# Rime词典拼音修正工具

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen.svg)](https://github.com/your-repo/rime-dict-processor)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux-blue.svg)](https://github.com/your-repo/rime-dict-processor)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

一个用于为Rime词典文件添加声调标记的工具，支持批量处理和多种词典格式。

## ✨ 特性

- 🎯 **自动拼音标注** - 为汉字添加准确的声调标记
- ✅ 保留辅助码和后缀（如 `;sc`、`[um]` 等）
- ✅ 支持批量处理目录和单个文件
- ✅ 支持自定义拼音数据
- ✅ 命令行界面，支持参数配置
- ✅ 跨平台静态可执行文件

## 使用方法

### 1. 快速开始

```bash
# 创建默认配置文件
./rime-dict-processor.exe --create-config

# 使用默认配置处理文件
./rime-dict-processor.exe
```

### 2. 命令行参数

```bash
# 指定输入输出目录
./rime-dict-processor.exe -i ./词典文件 -o ./处理结果

# 使用自定义配置文件
./rime-dict-processor.exe -c my-config.ini

# 指定自定义拼音数据目录
./rime-dict-processor.exe -d ./my-pinyin-data

# 查看帮助
./rime-dict-processor.exe --help
```

### 3. 配置文件

配置文件 `config.ini` 示例：

```ini
[Settings]
input_dir = ./input
output_dir = ./output
custom_dir = ./pinyin_data
aux_sep_regex = [;\[]
```

## 目录结构

```
工作目录/
├── rime-dict-processor.exe  # 主程序
├── config.ini              # 配置文件（可选）
├── input/                   # 输入目录
│   ├── 词典文件1.dict.yaml
│   └── 用户词典.userdb.txt
├── output/                  # 输出目录
└── pinyin_data/            # 自定义拼音数据（可选）
    ├── 单字.dict.yaml
    └── 词组.dict.yaml
```

## 支持的文件格式

### 普通词表格式
```
汉字	拼音
编码	bian ma
程序	cheng xu;sc
```

### 用户词典格式 (userdb)
```
#@/db_type	userdb
bian ma	编码	1
cheng xu;sc	程序	2
```

## 自定义拼音数据

在 `pinyin_data` 目录中放置自定义拼音文件：

```yaml
# 单字.dict.yaml
编	biān
码	mǎ

# 词组.dict.yaml  
编码	biān mǎ
程序	chéng xù
```

## 构建信息

- **构建平台**: Debian 12 (交叉编译)
- **目标平台**: Windows x64
- **Python版本**: 3.11.9
- **构建工具**: Wine + PyInstaller