import os
import socket

from flask import Flask, jsonify
import redis

app = Flask(__name__)

redis_client = redis.Redis(
    host=os.getenv("REDIS_HOST", "redis"),
    port=int(os.getenv("REDIS_PORT", 6379)),
    decode_responses=True,
    socket_connect_timeout=3,
    socket_timeout=3
)


@app.route("/")
def home():
    return jsonify({
        "application": "Docker Swarm Lab",
        "service": "Flask Backend",
        "hostname": socket.gethostname(),
        "message": "Backend is working!"
    })


@app.route("/api/")
def api():
    visits = redis_client.incr("total_visits")

    return jsonify({
        "application": "Docker Swarm Lab",
        "backend": "Flask",
        "hostname": socket.gethostname(),
        "visits": visits
    })


@app.route("/health")
def health():
    redis_client.ping()

    return jsonify({
        "status": "healthy",
        "hostname": socket.gethostname()
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
