# AWS Lambda with Requests Layer Deployment

このプロジェクトは、PythonのrequestsライブラリをLambdaレイヤーとして使用するシンプルなLambda関数を、GitHub Actionsで自動デプロイするためのセットアップです。

## プロジェクト構成

```
lambda-deploy/
├── src/
│   └── lambda/
│       ├── lambda_function.py       # メインのLambda関数
│       └── requirements.txt         # Pythonの依存関係
├── infrastructure/
│   └── template.yaml               # SAMテンプレート
├── scripts/
│   └── create_layer.sh             # レイヤー作成スクリプト
├── tests/
│   ├── test-event.json             # ローカルテスト用イベント
│   └── unit_test.py                # ユニットテスト
├── .github/
│   └── workflows/
│       └── deploy.yml              # GitHub Actionsワークフロー
├── Makefile                        # ローカル開発用コマンド
├── README.md
└── .gitignore
```

## セットアップ

### 1. AWS認証設定（ベストプラクティス）

最小権限の原則に従い、2つのIAMロールを作成します。

#### 1-1. CloudFormation用サービスロールの作成

CloudFormationが実際のリソースを作成するためのロールです。

**信頼ポリシー:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudformation.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

**権限ポリシー:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "lambda:*"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::aws-sam-cli-managed-default-*",
        "arn:aws:s3:::aws-sam-cli-managed-default-*/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:GetRole",
        "iam:TagRole"
      ],
      "Resource": "arn:aws:iam::*:role/lambda-deploy-*"
    },
    {
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::*:role/lambda-deploy-*",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": "lambda.amazonaws.com"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:DeleteLogGroup",
        "logs:DescribeLogGroups",
        "logs:PutRetentionPolicy",
        "logs:TagLogGroup"
      ],
      "Resource": "arn:aws:logs:*:*:log-group:/aws/lambda/lambda-deploy-*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "cloudformation:CreateChangeSet",
        "cloudformation:DescribeChangeSet",
        "cloudformation:ExecuteChangeSet",
        "cloudformation:DescribeStacks",
        "cloudformation:GetTemplate"
      ],
      "Resource": "*"
    }
  ]
}
```

**注意:**
- `Resource: "arn:aws:iam::*:role/lambda-deploy-*"` は、SAMが自動作成するロール名 `lambda-deploy-{env}-SimpleLambdaFunctionRole-{suffix}` にマッチします
- スタック名を変更する場合は、このパターンも更新してください

#### 1-2. GitHub Actions用IAMロールの作成

GitHub ActionsがCloudFormationを実行するための最小権限ロールです。

**信頼ポリシー（GitHub Actionsからのアクセスを許可）:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:*"
        }
      }
    }
  ]
}
```

**権限ポリシー（最小権限）:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudformation:CreateStack",
        "cloudformation:UpdateStack",
        "cloudformation:DeleteStack",
        "cloudformation:DescribeStacks",
        "cloudformation:DescribeStackEvents",
        "cloudformation:GetTemplate",
        "cloudformation:GetTemplateSummary",
        "cloudformation:ValidateTemplate",
        "cloudformation:CreateChangeSet",
        "cloudformation:DescribeChangeSet",
        "cloudformation:ExecuteChangeSet",
        "cloudformation:DeleteChangeSet"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "lambda:InvokeFunction",
      "Resource": "arn:aws:lambda:*:*:function:*-simple-lambda"
    },
    {
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::YOUR_ACCOUNT_ID:role/CloudFormationServiceRole",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": "cloudformation.amazonaws.com"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:ListBucketVersions",
        "s3:GetBucketLocation",
        "s3:DeleteObject",
        "s3:DeleteObjectVersion",
        "s3:DeleteBucket",
        "s3:PutBucketTagging",
        "s3:GetBucketTagging",
        "s3:PutObjectTagging",
        "s3:GetObjectTagging",
        "s3:PutEncryptionConfiguration",
        "s3:GetEncryptionConfiguration",
        "s3:PutBucketVersioning",
        "s3:GetBucketVersioning",
        "s3:PutBucketPublicAccessBlock",
        "s3:GetBucketPublicAccessBlock",
        "s3:PutBucketPolicy",
        "s3:GetBucketPolicy",
        "s3:DeleteBucketPolicy"
      ],
      "Resource": [
        "arn:aws:s3:::aws-sam-cli-managed-default-*",
        "arn:aws:s3:::aws-sam-cli-managed-default-*/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "s3:ListAllMyBuckets",
      "Resource": "*"
    }
  ]
}
```

**各権限の説明:**
- **CloudFormation権限**: スタックの作成・更新・削除に必須
- **Lambda InvokeFunction**: デプロイ後のテスト用（オプション、削除可能）
- **iam:PassRole**: CloudFormationサービスロールを渡すために必須
- **S3権限**: `--resolve-s3`でマネージドS3バケットを作成・管理するために必須（SAM CLIが使用）
- **s3:ListAllMyBuckets**: `make delete-stack`でS3バケット一覧を取得するために必須

**ポイント:**
- GitHub Actions用ロールは`iam:CreateRole`などの強い権限を**持たない**
- CloudFormationにサービスロールを渡す（PassRole）権限だけを持つ
- 実際のリソース作成・削除はCloudFormationサービスロールが行う

**スタック削除について:**
- `make delete-stack`や`aws cloudformation delete-stack`を実行する際も、同じCloudFormationサービスロールを使用します
- スタック削除時、CloudFormationサービスロールが実際のリソース削除を実行します（Lambda関数、レイヤー、IAMロール、CloudWatch Logsロググループなど）
- ローカル開発者やGitHub Actionsロールには、`cloudformation:DeleteStack`と`iam:PassRole`の権限があれば十分です
- CloudFormationサービスロールには、上記のポリシーに含まれる削除権限（`lambda:DeleteFunction`、`iam:DeleteRole`、`logs:DeleteLogGroup`など）が必要です

#### 1-3. ローカル開発用IAMユーザー/ロールの作成（オプション）

ローカルからデプロイする場合は、以下のいずれかを使用：

**オプションA: IAMユーザーを作成**
- GitHub Actions用ロールと同じ権限ポリシーをアタッチ
- アクセスキーを発行して `aws configure` で設定

**オプションB: AssumeRoleを使用**
- 既存のIAMユーザーに、CloudFormationサービスロールへの`iam:PassRole`権限を付与
- 信頼ポリシーでIAMユーザーからのAssumeを許可

**注意:** ローカル開発では`CLOUDFORMATION_ROLE_ARN`環境変数の設定が必要です。

#### 1-4. GitHub Secretsの設定

GitHub リポジトリのSecrets で以下を設定:
- `AWS_ROLE_ARN`: GitHub Actions用IAMロールのARN
- `CLOUDFORMATION_ROLE_ARN`: CloudFormation用サービスロールのARN

### 2. デプロイ

mainブランチにプッシュすると自動デプロイされます：
- `main` → `prod`環境
- `develop` → `staging`環境
- その他 → `dev`環境

手動デプロイも可能です（GitHub ActionsのWorkflow Dispatch）。

## ローカル開発

### 必要なツール
- AWS CLI
- AWS SAM CLI
- **Docker（推奨）** または Python 3.11

**Dockerを使用する場合（推奨）:**
- ローカルのPythonバージョンに関係なく、Lambda環境と同じPython 3.11でレイヤーを構築
- 容量を節約（追加のPythonインストール不要）
- `make layer`が自動的にDockerを検出して使用

**ローカルPythonを使用する場合:**
- Python 3.11が必要
- Dockerがない環境でも動作

### コマンド

```bash
# ヘルプを表示
make help

# レイヤーを作成（Dockerがあれば自動使用、なければローカルPython）
make layer

# Dockerを明示的に使用してレイヤー作成
make layer-docker

# ローカルPythonを使用してレイヤー作成
make layer-local

# レイヤー情報を表示
make layer-info

# レイヤーを強制再作成（キャッシュ無視）
make force-layer

# ビルド
make build

# ローカルでLambda関数をテスト（AWSへのデプロイ不要）
make local-test

# ユニットテスト実行
cd tests && python -m pytest unit_test.py -v
```

### AWSへのデプロイ（ローカル開発者向け）

**前提条件:**
- AWS認証情報が設定されている（`aws configure`または環境変数）
- ローカル開発用のIAMユーザー/ロールに必要な権限がある
- `CLOUDFORMATION_ROLE_ARN`環境変数を設定

```bash
# 環境変数を設定
export CLOUDFORMATION_ROLE_ARN=arn:aws:iam::YOUR_ACCOUNT_ID:role/CloudFormationServiceRole

# デプロイ（dev環境）
make deploy

# 本番環境にデプロイ
make deploy ENV=prod

# AWS上の関数をテスト
make test

# スタックの削除（Lambda関数、レイヤー、IAMロールなどすべて削除）
make delete-stack

# 本番環境のスタックを削除
make delete-stack ENV=prod

# ローカルのビルド成果物をクリーンアップ
make clean
```

## Lambda関数の仕様

- ランタイム: Python 3.11
- ハンドラー: `lambda_function.lambda_handler`
- タイムアウト: 30秒
- メモリ: 128MB
- 依存関係: requests（Lambdaレイヤーとして提供）

### イベント形式

```json
{
  "url": "https://example.com/api"
}
```

URLが指定されない場合は、デフォルトで `https://httpbin.org/json` にリクエストを送信します。

## レイヤー最適化機能

### サイズ最適化
- 不要なファイル（テスト、ドキュメント、キャッシュ等）を自動削除
- 最高圧縮率（-9）でzip作成
- requests特有の不要モジュールを除去
- 通常の50-70%程度にサイズ削減

### キャッシュ機能  
- `requirements.txt`のハッシュベースでキャッシュ判定
- 依存関係に変更がない場合は再作成をスキップ
- GitHub Actionsでもキャッシュを活用してビルド時間を短縮

### 使用方法
```bash
# 通常作成（キャッシュチェック有り）
make layer

# 強制再作成
make force-layer

# レイヤー状態確認
make layer-info
```