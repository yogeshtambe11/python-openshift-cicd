from flask import Flask, jsonify

app = Flask(__name__)


@app.get("/")
def index():
    return jsonify(
        application="python-openshift-cicd",
        message="Hello from OpenShift",
        status="running",
    )


@app.get("/health")
def health():
    return jsonify(status="ok"), 200

