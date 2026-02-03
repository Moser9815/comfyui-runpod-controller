"""
ComfyUI RunPod Controller - Web Interface
Designed for mobile (iPad) access via Google Cloud Run
Protected by Google Sign-In
"""

import os
import functools
from flask import Flask, render_template, jsonify, request, redirect, session

try:
    import runpod
except ImportError:
    import subprocess
    import sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "runpod", "-q"])
    import runpod

try:
    from google.oauth2 import id_token
    from google.auth.transport import requests as google_requests
except ImportError:
    import subprocess
    import sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "google-auth", "-q"])
    from google.oauth2 import id_token
    from google.auth.transport import requests as google_requests

import requests as http_requests

app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", os.urandom(32))

# Configuration - set via environment variables
API_KEY = os.environ.get("RUNPOD_API_KEY", "")
NETWORK_VOLUME_ID = os.environ.get("RUNPOD_VOLUME_ID", "")
GOOGLE_CLIENT_ID = os.environ.get("GOOGLE_CLIENT_ID", "")
ALLOWED_EMAILS = os.environ.get("ALLOWED_EMAILS", "detroitinnovation@gmail.com").lower().split(",")
CIVITAI_API_TOKEN = os.environ.get("CIVITAI_API_TOKEN", "")

runpod.api_key = API_KEY

POD_NAME = "comfyui-ondemand"

GPU_TIERS = {
    "budget": [
        "NVIDIA GeForce RTX 3090",
        "NVIDIA RTX A5000",
    ],
    "high": [
        "NVIDIA GeForce RTX 4090",
        "NVIDIA RTX A6000",
        "NVIDIA GeForce RTX 3090",
    ],
    "ultra": [
        "NVIDIA L40S",
        "NVIDIA A100 80GB PCIe",
        "NVIDIA A100-SXM4-80GB",
        "NVIDIA H100 PCIe",
        "NVIDIA H100 80GB HBM3",
        "NVIDIA GeForce RTX 4090",
    ],
}


def require_auth(f):
    """Decorator to require Google Sign-In"""
    @functools.wraps(f)
    def decorated(*args, **kwargs):
        # Skip auth if no client ID configured (for testing)
        if not GOOGLE_CLIENT_ID:
            return f(*args, **kwargs)

        # Check session
        if session.get("email") and session.get("email").lower() in ALLOWED_EMAILS:
            return f(*args, **kwargs)

        # Check Authorization header (for API calls)
        auth_header = request.headers.get("Authorization", "")
        if auth_header.startswith("Bearer "):
            token = auth_header[7:]
            try:
                idinfo = id_token.verify_oauth2_token(
                    token, google_requests.Request(), GOOGLE_CLIENT_ID
                )
                email = idinfo.get("email", "").lower()
                if email in ALLOWED_EMAILS:
                    return f(*args, **kwargs)
            except Exception:
                pass

        return jsonify({"error": "unauthorized", "message": "Please sign in"}), 401
    return decorated


def find_pod():
    """Find existing ComfyUI pod"""
    pods = runpod.get_pods()
    for pod in pods:
        if pod["name"] == POD_NAME:
            return pod
    return None


def check_comfyui_health(url):
    """Check if ComfyUI is actually responding"""
    try:
        # ComfyUI has a /system_stats endpoint we can ping
        response = http_requests.get(f"{url}/system_stats", timeout=5)
        return response.status_code == 200
    except:
        return False


@app.route("/")
def index():
    return render_template("index.html",
                         google_client_id=GOOGLE_CLIENT_ID,
                         auth_required=bool(GOOGLE_CLIENT_ID))


@app.route("/api/auth/verify", methods=["POST"])
def verify_token():
    """Verify Google Sign-In token and create session"""
    if not GOOGLE_CLIENT_ID:
        return jsonify({"success": True, "email": "auth-disabled"})

    data = request.get_json() or {}
    token = data.get("credential", "")

    try:
        idinfo = id_token.verify_oauth2_token(
            token, google_requests.Request(), GOOGLE_CLIENT_ID
        )
        email = idinfo.get("email", "").lower()

        if email not in ALLOWED_EMAILS:
            return jsonify({"success": False, "message": f"Access denied for {email}"}), 403

        session["email"] = email
        session["name"] = idinfo.get("name", email)

        return jsonify({"success": True, "email": email, "name": session["name"]})
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 401


@app.route("/api/auth/logout", methods=["POST"])
def logout():
    """Clear session"""
    session.clear()
    return jsonify({"success": True})


@app.route("/api/auth/status")
def auth_status():
    """Check if user is authenticated"""
    if not GOOGLE_CLIENT_ID:
        return jsonify({"authenticated": True, "auth_required": False})

    if session.get("email"):
        return jsonify({
            "authenticated": True,
            "auth_required": True,
            "email": session["email"],
            "name": session.get("name", session["email"])
        })
    return jsonify({"authenticated": False, "auth_required": True})


@app.route("/api/status")
@require_auth
def api_status():
    """Get current pod status"""
    pod = find_pod()
    if not pod:
        return jsonify({
            "exists": False,
            "status": "No pod",
            "message": "No ComfyUI pod exists. Click Start to create one."
        })

    status = pod.get("desiredStatus", "UNKNOWN")
    runtime = pod.get("runtime")
    gpu = pod.get("machine", {}).get("gpuDisplayName", "Unknown")
    cost = pod.get("costPerHr", 0)

    result = {
        "exists": True,
        "id": pod["id"],
        "status": status,
        "gpu": gpu,
        "cost": f"${cost}/hr" if cost else "N/A",
        "console": "https://www.runpod.io/console/pods",
    }

    if runtime and runtime.get("ports"):
        comfy_url = f"https://{pod['id']}-8188.proxy.runpod.net"
        result["url"] = comfy_url

        # Check if ComfyUI is actually responding
        comfy_healthy = check_comfyui_health(comfy_url)
        result["comfy_ready"] = comfy_healthy
        result["ready"] = comfy_healthy

        if not comfy_healthy:
            result["message"] = "Pod running, ComfyUI starting up..."
    else:
        result["ready"] = False
        result["comfy_ready"] = False
        if status == "RUNNING":
            result["message"] = "Pod is starting up..."

    return jsonify(result)


@app.route("/api/start", methods=["POST"])
@require_auth
def api_start():
    """Start or create ComfyUI pod"""
    data = request.get_json() or {}
    tier = data.get("tier", "high")
    gpu_types = GPU_TIERS.get(tier, GPU_TIERS["high"])

    pod = find_pod()

    if pod:
        if pod["desiredStatus"] == "RUNNING":
            return jsonify({
                "success": True,
                "message": "Pod is already running",
                "id": pod["id"]
            })
        else:
            runpod.resume_pod(pod["id"], gpu_count=1)
            return jsonify({
                "success": True,
                "message": "Resuming pod...",
                "id": pod["id"]
            })

    for gpu_type in gpu_types:
        try:
            pod = runpod.create_pod(
                name=POD_NAME,
                image_name="runpod/pytorch:2.1.0-py3.10-cuda11.8.0-devel-ubuntu22.04",
                gpu_type_id=gpu_type,
                cloud_type="ALL",
                network_volume_id=NETWORK_VOLUME_ID,
                volume_in_gb=0,
                container_disk_in_gb=20,
                ports="8188/http,22/tcp",
                volume_mount_path="/workspace",
                env={"CIVITAI_API_TOKEN": CIVITAI_API_TOKEN},
            )
            return jsonify({
                "success": True,
                "message": f"Created pod with {gpu_type}",
                "id": pod["id"],
                "gpu": gpu_type
            })
        except Exception as e:
            if "no longer any instances available" not in str(e).lower():
                return jsonify({
                    "success": False,
                    "message": f"Error: {str(e)}"
                })

    return jsonify({
        "success": False,
        "message": "No GPUs available. Try again in a few minutes or try a different tier."
    })


@app.route("/api/stop", methods=["POST"])
@require_auth
def api_stop():
    """Stop pod (keeps network volume)"""
    pod = find_pod()
    if not pod:
        return jsonify({"success": False, "message": "No pod found"})

    runpod.stop_pod(pod["id"])
    return jsonify({
        "success": True,
        "message": "Pod stopped. Storage costs ~$0.20/day."
    })


@app.route("/api/terminate", methods=["POST"])
@require_auth
def api_terminate():
    """Fully terminate pod"""
    pod = find_pod()
    if not pod:
        return jsonify({"success": False, "message": "No pod found"})

    runpod.terminate_pod(pod["id"])
    return jsonify({
        "success": True,
        "message": "Pod terminated."
    })


@app.route("/api/setup-command")
@require_auth
def api_setup_command():
    """Get the setup command for the web terminal"""
    gist_url = "https://gist.githubusercontent.com/Moser9815/b4517755d84d56d1829e3cf3e1676372/raw"
    if CIVITAI_API_TOKEN:
        command = f'export CIVITAI_API_TOKEN={CIVITAI_API_TOKEN} && curl -sL "{gist_url}?$(date +%s)" | bash'
    else:
        command = f'curl -sL "{gist_url}?$(date +%s)" | bash'
    return jsonify({"command": command})


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=False)
