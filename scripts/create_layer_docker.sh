#!/bin/bash

set -e

REQUIREMENTS_FILE="src/lambda/requirements.txt"
LAYER_DIR="layer"
LAYER_ZIP="requests-layer.zip"
LAYER_HASH_FILE=".layer_hash"

# requirements.txtのハッシュを計算
CURRENT_HASH=$(sha256sum "$REQUIREMENTS_FILE" | cut -d' ' -f1)

# 前回のハッシュと比較
if [ -f "$LAYER_HASH_FILE" ] && [ -f "$LAYER_ZIP" ]; then
    PREVIOUS_HASH=$(cat "$LAYER_HASH_FILE" 2>/dev/null || echo "")
    if [ "$CURRENT_HASH" = "$PREVIOUS_HASH" ]; then
        echo "Dependencies unchanged. Skipping layer creation."
        echo "Existing layer: $LAYER_ZIP"
        exit 0
    fi
fi

echo "Creating optimized Lambda layer using Docker..."

# 既存のレイヤーディレクトリをクリーンアップ
rm -rf "$LAYER_DIR"
rm -f "$LAYER_ZIP"

# Layer用のディレクトリを作成
mkdir -p "$LAYER_DIR/python/lib/python3.11/site-packages"

# Dockerを使用してPython 3.11環境でレイヤーをビルド
docker run --rm \
    -v "$(pwd)/$REQUIREMENTS_FILE:/requirements.txt:ro" \
    -v "$(pwd)/$LAYER_DIR/python:/layer/python" \
    -v "$(pwd)/scripts/layer_cleanup.py:/layer_cleanup.py:ro" \
    python:3.11-slim \
    bash -c "
        echo 'Installing dependencies...'
        pip install \
            --target /layer/python/lib/python3.11/site-packages/ \
            --requirement /requirements.txt \
            --no-cache-dir \
            --upgrade && \

        echo 'Optimizing layer size...' && \
        cd /layer/python/lib/python3.11/site-packages && \

        # .pyc ファイルとキャッシュディレクトリを削除
        find . -type f -name '*.pyc' -delete && \
        find . -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true && \
        find . -type d -name '*.egg-info' -exec rm -rf {} + 2>/dev/null || true && \

        # テストファイルとドキュメントを削除
        find . -type d -name 'tests' -exec rm -rf {} + 2>/dev/null || true && \
        find . -type d -name 'test' -exec rm -rf {} + 2>/dev/null || true && \
        find . -type f -name '*.md' -delete && \
        find . -type f -name '*.rst' -delete && \
        find . -type f -name '*.txt' -delete && \
        find . -type f -name '*.cfg' -delete && \

        # 不要な実行ファイルを削除
        find . -name '*.exe' -delete && \
        find . -name '*.bat' -delete && \

        # 開発用ファイルを削除
        find . -name '.git*' -delete 2>/dev/null || true && \
        find . -name '*.c' -delete && \
        find . -name '*.h' -delete && \
        find . -name '*.pyx' -delete && \

        # 追加の最適化
        cd /layer && \
        python3 /layer_cleanup.py /layer/python/lib/python3.11/site-packages
    "

# Layer zipファイルを作成（圧縮率を最適化）
cd "$LAYER_DIR"
zip -r9 "../$LAYER_ZIP" . > /dev/null
cd ..

# ハッシュを保存
echo "$CURRENT_HASH" > "$LAYER_HASH_FILE"

# サイズ情報を表示
LAYER_SIZE=$(du -h "$LAYER_ZIP" | cut -f1)
echo "Layer zip file created: $LAYER_ZIP (size: $LAYER_SIZE)"
echo "Layer hash saved: $CURRENT_HASH"
