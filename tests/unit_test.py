import json
import pytest
import sys
import os

# パスを追加してLambda関数をインポート
sys.path.append(os.path.join(os.path.dirname(__file__), '../src/lambda'))

from lambda_function import lambda_handler

class TestLambdaFunction:

    def test_lambda_handler_default_url(self):
        """デフォルトURLでのテスト"""
        event = {}
        context = {}

        response = lambda_handler(event, context)

        assert response['statusCode'] == 200
        body = json.loads(response['body'])
        assert 'message' in body
        assert body['message'] == 'Request successful'

    def test_lambda_handler_custom_url(self):
        """カスタムURLでのテスト"""
        event = {'url': 'https://httpbin.org/json'}
        context = {}

        response = lambda_handler(event, context)

        assert response['statusCode'] == 200
        body = json.loads(response['body'])
        assert 'message' in body
        assert body['message'] == 'Request successful'
        assert 'status_code' in body
        assert 'response_data' in body

    def test_lambda_handler_with_test_event_json(self):
        """test-event.jsonを使ったテスト"""
        test_event_path = os.path.join(os.path.dirname(__file__), 'test-event.json')

        with open(test_event_path, 'r') as f:
            event = json.load(f)

        context = {}
        response = lambda_handler(event, context)

        assert response['statusCode'] == 200
        body = json.loads(response['body'])
        assert 'message' in body
        assert body['message'] == 'Request successful'
        assert 'status_code' in body
        assert 'response_data' in body

    def test_lambda_handler_invalid_url(self):
        """無効なURLでのテスト"""
        event = {'url': 'invalid-url'}
        context = {}

        response = lambda_handler(event, context)

        assert response['statusCode'] == 500
        body = json.loads(response['body'])
        assert 'error' in body
        assert 'Request failed' in body['error']