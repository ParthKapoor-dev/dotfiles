#!/usr/bin/env python3
"""Fake greetd IPC server for rehearsing the greeter (`nox greeter test` / `nested`).

Speaks greetd's protocol (u32 native-endian length + JSON) on the socket given as argv[1]:
create_session -> secret "Password:" prompt; the right password (NOX_GREETER_FAKE_PW, default
"nox") -> success, anything else -> auth_error; start_session -> success and the command is
logged (nothing is started). Every request is logged to stdout.
"""
import json, os, socket, struct, sys

path = sys.argv[1]
password = os.environ.get("NOX_GREETER_FAKE_PW", "nox")
# like real greetd right after a failed attempt: refuse the next create_session once
refuse_after_fail = os.environ.get("NOX_GREETER_FAKE_REFUSE", "") != ""
state = {"refuse": False}


def send(c, obj):
    data = json.dumps(obj).encode()
    c.sendall(struct.pack("=I", len(data)) + data)


def recv(c):
    head = b""
    while len(head) < 4:
        chunk = c.recv(4 - len(head))
        if not chunk:
            return None
        head += chunk
    (n,) = struct.unpack("=I", head)
    body = b""
    while len(body) < n:
        chunk = c.recv(n - len(body))
        if not chunk:
            return None
        body += chunk
    return json.loads(body)


def serve(c):
    user = None
    authed = False
    while True:
        req = recv(c)
        if req is None:
            return
        kind = req.get("type")
        shown = dict(req)
        if "response" in shown and shown["response"]:
            shown["response"] = "*" * len(shown["response"])
        print("req", json.dumps(shown), flush=True)
        if kind == "create_session":
            if state["refuse"]:
                state["refuse"] = False
                send(c, {"type": "error", "error_type": "error",
                         "description": "Unable to send message: Connection refused (os error 111)"})
                continue
            user, authed = req.get("username"), False
            send(c, {"type": "auth_message", "auth_message_type": "secret", "auth_message": "Password: "})
        elif kind == "post_auth_message_response":
            if req.get("response") == password:
                authed = True
                send(c, {"type": "success"})
            else:
                user = None
                state["refuse"] = refuse_after_fail
                send(c, {"type": "error", "error_type": "auth_error", "description": "pam_authenticate: AUTH_ERR"})
        elif kind == "start_session":
            if authed:
                print("LAUNCH", user, json.dumps(req.get("cmd")), flush=True)
                send(c, {"type": "success"})
            else:
                send(c, {"type": "error", "error_type": "error", "description": "session not authenticated"})
        elif kind == "cancel_session":
            user, authed = None, False
            send(c, {"type": "success"})
        else:
            send(c, {"type": "error", "error_type": "error", "description": "unknown request"})


if os.path.exists(path):
    os.unlink(path)
srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
srv.bind(path)
srv.listen(4)
print("fake greetd on", path, flush=True)
while True:
    conn, _ = srv.accept()
    try:
        serve(conn)
    except Exception as e:  # keep serving after a client error
        print("client error:", e, flush=True)
    finally:
        conn.close()
