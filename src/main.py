#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Rime词典拼音修正工具 - 可执行版本
支持命令行参数和配置文件
"""

import os
import sys
import argparse
import configparser
from pathlib import Path

# 获取当前脚本目录并添加到sys.path
current_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, current_dir)

# 导入处理模块功能
try:
    import rime_processor_embedded as rime_processor
    load_custom_pinyin_from_directory = rime_processor.load_custom_pinyin_from_directory
    process_files = rime_processor.process_files
    AUX_SEP_REGEX = rime_processor.AUX_SEP_REGEX
    print("✓ 使用嵌入式处理模块")
except ImportError as e:
    print(f"❌ 无法加载处理模块: {e}")
    sys.exit(1)

def get_script_dir():
    """获取脚本所在目录"""
    if getattr(sys, 'frozen', False):
        # 如果是打包后的可执行文件
        return Path(sys.executable).parent
    else:
        # 如果是Python脚本
        return Path(__file__).parent

def load_config(config_file=None):
    """加载配置文件"""
    config = configparser.ConfigParser()
    
    # 默认配置
    config['DEFAULT'] = {
        'input_dir': './input',
        'output_dir': './output',
        'custom_dir': './pinyin_data',
        'aux_sep_regex': r'[;\[]'
    }
    
    # 尝试加载配置文件
    if config_file and os.path.exists(config_file):
        config.read(config_file, encoding='utf-8')
    else:
        # 查找默认配置文件
        script_dir = get_script_dir()
        default_config = script_dir / 'config.ini'
        if default_config.exists():
            config.read(str(default_config), encoding='utf-8')
    
    return config

def create_default_config():
    """创建默认配置文件"""
    script_dir = get_script_dir()
    config_file = script_dir / 'config.ini'
    
    config = configparser.ConfigParser()
    config['Settings'] = {
        'input_dir': './input',
        'output_dir': './output', 
        'custom_dir': './pinyin_data',
        'aux_sep_regex': r'[;\[]'
    }
    
    with open(config_file, 'w', encoding='utf-8') as f:
        config.write(f)
    
    print(f"已创建默认配置文件: {config_file}")
    return config_file

def main():
    parser = argparse.ArgumentParser(
        description='Rime词典拼音修正工具',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例用法:
  %(prog)s                           # 使用默认配置
  %(prog)s -i ./input -o ./output    # 指定输入输出目录
  %(prog)s -c config.ini             # 使用指定配置文件
  %(prog)s --create-config           # 创建默认配置文件
        """)
    
    parser.add_argument('-i', '--input', 
                       help='输入目录或文件路径')
    parser.add_argument('-o', '--output',
                       help='输出目录或文件路径')
    parser.add_argument('-d', '--custom-dir',
                       help='自定义拼音数据目录')
    parser.add_argument('-c', '--config',
                       help='配置文件路径')
    parser.add_argument('--create-config', action='store_true',
                       help='创建默认配置文件')
    parser.add_argument('--version', action='version', version='%(prog)s 1.0.0')
    
    args = parser.parse_args()
    
    # 如果请求创建配置文件
    if args.create_config:
        create_default_config()
        return
    
    # 加载配置
    config = load_config(args.config)
    
    # 获取参数值（命令行参数优先于配置文件）
    input_dir = args.input or config['DEFAULT']['input_dir']
    output_dir = args.output or config['DEFAULT']['output_dir']
    custom_dir = args.custom_dir or config['DEFAULT']['custom_dir']
    
    # 转换为绝对路径
    script_dir = get_script_dir()
    
    if not os.path.isabs(input_dir):
        input_dir = script_dir / input_dir
    if not os.path.isabs(output_dir):
        output_dir = script_dir / output_dir
    if not os.path.isabs(custom_dir):
        custom_dir = script_dir / custom_dir
    
    input_dir = str(input_dir)
    output_dir = str(output_dir)
    custom_dir = str(custom_dir)
    
    # 检查输入路径（更宽松的检查）
    if not os.path.exists(input_dir) and not os.path.isfile(input_dir):
        # 如果是Wine环境中的路径，尝试转换
        if input_dir.startswith('Z:'):
            linux_path = input_dir.replace('Z:', '', 1).replace('\\', '/')
            if os.path.exists(linux_path):
                input_dir = linux_path
            else:
                print(f"错误: 输入路径不存在: {input_dir}")
                print("请检查路径或使用 --create-config 创建配置文件")
                sys.exit(1)
        else:
            print(f"错误: 输入路径不存在: {input_dir}")
            print("请检查路径或使用 --create-config 创建配置文件")
            sys.exit(1)
    
    # 显示配置信息
    print("=== Rime词典拼音修正工具 ===")
    print(f"输入路径: {input_dir}")
    print(f"输出路径: {output_dir}")
    print(f"自定义拼音目录: {custom_dir}")
    print("=" * 30)
    
    try:
        # 加载自定义拼音数据
        load_custom_pinyin_from_directory(custom_dir)
        
        # 处理文件
        process_files(input_dir, output_dir)
        
        print("✓ 全部文件处理完成")
        
    except Exception as e:
        print(f"错误: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
