import os
import base64
import json
import urllib.request
import urllib.error

OWNER = "mkiw1464-debug"
REPO = "katanya"
BRANCH = "main"

token = "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"

for root, dirs, files in os.walk("."):
    dirs[:] = [d for d in dirs if d != ".git"]

    for filename in files:
        if filename == "upload.py":
            continue

        full = os.path.join(root, filename)
        path = os.path.relpath(full, ".").replace("\\", "/")

        print("Uploading:", path)

        try:
            with open(full, "rb") as f:
                content = base64.b64encode(f.read()).decode()
        except Exception as e:
            print("FAILED READ:", path, e)
            continue

        url = (
            f"https://api.github.com/repos/"
            f"{OWNER}/{REPO}/contents/{path}"
        )

        headers = {
            "Authorization": "Bearer " + token,
            "Accept": "application/vnd.github+json",
            "User-Agent": "iPhone-GitHub-Uploader"
        }

        sha = None

        check_req = urllib.request.Request(
            url + "?ref=" + BRANCH,
            headers=headers
        )

        try:
            with urllib.request.urlopen(check_req) as response:
                existing = json.loads(
                    response.read().decode()
                )
                sha = existing.get("sha")

        except urllib.error.HTTPError as e:
            if e.code != 404:
                print("CHECK FAILED:", path)
                print(e.read().decode())
                continue

        data = {
            "message": "Upload " + path,
            "content": content,
            "branch": BRANCH
        }

        if sha:
            data["sha"] = sha

        upload_req = urllib.request.Request(
            url,
            data=json.dumps(data).encode(),
            method="PUT",
            headers={
                **headers,
                "Content-Type": "application/json"
            }
        )

        try:
            with urllib.request.urlopen(upload_req) as response:
                print("OK:", path)

        except urllib.error.HTTPError as e:
            print("FAILED:", path, e.code)
            print(e.read().decode())

        except Exception as e:
            print("ERROR:", path, e)

print("")
print("DONE")
