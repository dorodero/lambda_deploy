#!/usr/bin/env python3
"""
レイヤー最適化用スクリプト
特定のライブラリに対してより詳細な最適化を行う
"""

import os
import shutil
from pathlib import Path
import argparse

def optimize_requests_library(packages_dir: Path):
    """requestsライブラリ特有の最適化"""
    print("Optimizing requests library...")
    
    # urllib3の不要なcontribモジュールを削除
    urllib3_contrib = packages_dir / "urllib3" / "contrib"
    if urllib3_contrib.exists():
        shutil.rmtree(urllib3_contrib)
        print("  Removed urllib3.contrib")
    
    # requests の extras を削除
    requests_dir = packages_dir / "requests"
    if requests_dir.exists():
        # 開発用ファイルを削除
        for pattern in ["*.pyi", "py.typed"]:
            for file in requests_dir.rglob(pattern):
                file.unlink()
                
def optimize_general(packages_dir: Path):
    """一般的な最適化"""
    print("Applying general optimizations...")
    
    # dist-info/METADATA ファイルのサイズを削減
    for dist_info in packages_dir.glob("*.dist-info"):
        metadata_file = dist_info / "METADATA"
        if metadata_file.exists():
            # メタデータファイルを最小限に
            with open(metadata_file, 'w') as f:
                f.write("Name: optimized\nVersion: 1.0.0\n")
    
    # LICENSE ファイルを削除（本番環境では注意）
    for license_file in packages_dir.rglob("LICENSE*"):
        if license_file.is_file():
            license_file.unlink()
    
    # NOTICE ファイルを削除
    for notice_file in packages_dir.rglob("NOTICE*"):
        if notice_file.is_file():
            notice_file.unlink()
            
    # examples ディレクトリを削除
    for examples_dir in packages_dir.rglob("examples"):
        if examples_dir.is_dir():
            shutil.rmtree(examples_dir)

def main():
    parser = argparse.ArgumentParser(description='Optimize Lambda layer')
    parser.add_argument('packages_dir', help='Path to site-packages directory')
    args = parser.parse_args()
    
    packages_dir = Path(args.packages_dir)
    
    if not packages_dir.exists():
        print(f"Error: {packages_dir} does not exist")
        return 1
        
    optimize_requests_library(packages_dir)
    optimize_general(packages_dir)
    
    print("Layer optimization completed")
    return 0

if __name__ == "__main__":
    exit(main())