#!/usr/bin/env python3
"""
S3バケットを完全に空にするスクリプト
すべてのオブジェクトバージョンと削除マーカーを削除します
"""
import sys
import boto3
from botocore.exceptions import ClientError

def empty_bucket(bucket_name, profile=None):
    """バケットを完全に空にする"""
    try:
        # セッションを作成
        if profile:
            session = boto3.Session(profile_name=profile)
            s3 = session.client('s3')
        else:
            s3 = boto3.client('s3')

        print(f"Emptying bucket: {bucket_name}")

        # ページネーション対応
        paginator = s3.get_paginator('list_object_versions')

        total_deleted = 0
        for page in paginator.paginate(Bucket=bucket_name):
            # バージョンを削除
            versions = page.get('Versions', [])
            delete_markers = page.get('DeleteMarkers', [])

            objects_to_delete = []

            for version in versions:
                objects_to_delete.append({
                    'Key': version['Key'],
                    'VersionId': version['VersionId']
                })

            for marker in delete_markers:
                objects_to_delete.append({
                    'Key': marker['Key'],
                    'VersionId': marker['VersionId']
                })

            if objects_to_delete:
                print(f"  Deleting {len(objects_to_delete)} objects/versions...")
                s3.delete_objects(
                    Bucket=bucket_name,
                    Delete={'Objects': objects_to_delete}
                )
                total_deleted += len(objects_to_delete)

        print(f"  Total deleted: {total_deleted} objects/versions")
        print(f"  Bucket {bucket_name} is now empty")
        return True

    except ClientError as e:
        print(f"Error: {e}", file=sys.stderr)
        return False

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: empty_bucket.py <bucket-name> [aws-profile]")
        sys.exit(1)

    bucket = sys.argv[1]
    profile = sys.argv[2] if len(sys.argv) > 2 else None

    success = empty_bucket(bucket, profile)
    sys.exit(0 if success else 1)
