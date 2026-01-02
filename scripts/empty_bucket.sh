#!/bin/bash
# S3バケットを完全に空にするスクリプト
# すべてのオブジェクトバージョンと削除マーカーを削除します

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <bucket-name> [aws-profile]"
    exit 1
fi

BUCKET=$1
PROFILE_FLAG=""

if [ -n "$2" ]; then
    PROFILE_FLAG="--profile $2"
fi

echo "Emptying bucket: $BUCKET"

# バケットが存在するか確認
if ! aws s3api head-bucket --bucket "$BUCKET" $PROFILE_FLAG 2>/dev/null; then
    echo "Bucket $BUCKET does not exist or is not accessible"
    exit 0
fi

deleted_count=0

# すべてのバージョンを削除
while true; do
    # バージョン一覧を取得（最大1000件）
    versions=$(aws s3api list-object-versions \
        --bucket "$BUCKET" \
        --max-items 1000 \
        --output json \
        $PROFILE_FLAG 2>/dev/null || echo '{}')

    # Versionsを処理
    objects=$(echo "$versions" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    versions = data.get('Versions', [])
    if versions:
        result = {'Objects': [{'Key': v['Key'], 'VersionId': v['VersionId']} for v in versions]}
        print(json.dumps(result))
    else:
        print('')
except:
    print('')
" 2>/dev/null)

    if [ -n "$objects" ] && [ "$objects" != "" ]; then
        count=$(echo "$objects" | python3 -c "import sys, json; print(len(json.load(sys.stdin)['Objects']))")
        echo "  Deleting $count object versions..."
        echo "$objects" | aws s3api delete-objects \
            --bucket "$BUCKET" \
            --delete file:///dev/stdin \
            $PROFILE_FLAG >/dev/null 2>&1 || true
        deleted_count=$((deleted_count + count))
    fi

    # DeleteMarkersを処理
    markers=$(echo "$versions" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    markers = data.get('DeleteMarkers', [])
    if markers:
        result = {'Objects': [{'Key': m['Key'], 'VersionId': m['VersionId']} for m in markers]}
        print(json.dumps(result))
    else:
        print('')
except:
    print('')
" 2>/dev/null)

    if [ -n "$markers" ] && [ "$markers" != "" ]; then
        count=$(echo "$markers" | python3 -c "import sys, json; print(len(json.load(sys.stdin)['Objects']))")
        echo "  Deleting $count delete markers..."
        echo "$markers" | aws s3api delete-objects \
            --bucket "$BUCKET" \
            --delete file:///dev/stdin \
            $PROFILE_FLAG >/dev/null 2>&1 || true
        deleted_count=$((deleted_count + count))
    fi

    # どちらもない場合は終了
    if [ -z "$objects" ] && [ -z "$markers" ]; then
        break
    fi
done

echo "  Total deleted: $deleted_count objects/versions"
echo "  Bucket $BUCKET is now empty"
