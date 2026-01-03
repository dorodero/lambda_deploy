import json
import requests

def lambda_handler(event, context):
    """
    シンプルなLambda関数 - HTTPリクエストを送信してレスポンスを返す
    API Gateway経由と直接呼び出しの両方に対応
    """
    try:
        # API Gateway経由の場合、bodyをパース
        if 'body' in event and isinstance(event['body'], str):
            try:
                body = json.loads(event['body'])
            except json.JSONDecodeError:
                body = {}
        else:
            # 直接呼び出しの場合
            body = event

        # HTTPリクエストを送信
        url = body.get('url', 'https://httpbin.org/json')
        response = requests.get(url, timeout=10)

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Request successful - Updated version',
                'status_code': response.status_code,
                'response_data': response.json() if response.headers.get('content-type', '').startswith('application/json') else response.text[:500]
            })
        }
    except requests.RequestException as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'Request failed: {str(e)}'
            })
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'Unexpected error: {str(e)}'
            })
        }