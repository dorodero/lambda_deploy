import json
import requests

def lambda_handler(event, context):
    """
    シンプルなLambda関数 - HTTPリクエストを送信してレスポンスを返す
    """
    try:
        # HTTPリクエストを送信
        url = event.get('url', 'https://httpbin.org/json')
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