"""Healthz Cloud Function.

ADR 0005 の判断に従い、外形監視で叩かれる /health を独立した最小依存の
Cloud Function として切り出す。重い SDK (genai / firestore) を読み込まない
ことでコールドスタートを最小化する。
"""

import functions_framework
from flask import jsonify


@functions_framework.http
def main(request):
    if request.method != "GET":
        body = {
            "type": "method_not_allowed",
            "title": "Method Not Allowed",
            "status": 405,
        }
        return jsonify(body), 405, {"Content-Type": "application/problem+json"}

    return jsonify({"status": "ok"}), 200

