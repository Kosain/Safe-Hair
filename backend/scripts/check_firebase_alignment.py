"""Print whether Flutter + backend point at the same Firebase project (safe-hair-274)."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

_REPO = Path(__file__).resolve().parent.parent.parent
_BACKEND = _REPO / "backend"
_MOBILE = _REPO / "mobile_app"


def main() -> int:
    from safe_hair_project import PROJECT_ID, resolve_service_account_path

    project_json = _REPO / "firebase" / "project.json"
    opts = _MOBILE / "lib" / "firebase_options.dart"
    gservices = _MOBILE / "android" / "app" / "google-services.json"
    firebaserc = _MOBILE / ".firebaserc"

    ok = True
    print(f"Expected Firebase project: {PROJECT_ID}\n")

    if project_json.is_file():
        data = json.loads(project_json.read_text(encoding="utf-8"))
        pid = data.get("projectId", "")
        print(f"  firebase/project.json     -> {pid} {'OK' if pid == PROJECT_ID else 'MISMATCH'}")
        ok &= pid == PROJECT_ID

    if opts.is_file():
        m = re.search(r"projectId:\s*'([^']+)'", opts.read_text(encoding="utf-8"))
        pid = m.group(1) if m else "?"
        print(f"  firebase_options.dart     -> {pid} {'OK' if pid == PROJECT_ID else 'MISMATCH'}")
        ok &= pid == PROJECT_ID

    if gservices.is_file():
        pid = json.loads(gservices.read_text(encoding="utf-8"))["project_info"]["project_id"]
        print(f"  google-services.json      -> {pid} {'OK' if pid == PROJECT_ID else 'MISMATCH'}")
        ok &= pid == PROJECT_ID

    if firebaserc.is_file():
        pid = json.loads(firebaserc.read_text(encoding="utf-8"))["projects"]["default"]
        print(f"  .firebaserc               -> {pid} {'OK' if pid == PROJECT_ID else 'MISMATCH'}")
        ok &= pid == PROJECT_ID

    path = resolve_service_account_path()
    if path:
        with open(path, encoding="utf-8") as f:
            sa_pid = json.load(f).get("project_id", "")
        print(f"  backend Admin SDK         -> {sa_pid} ({path}) OK")
        ok &= sa_pid == PROJECT_ID
    else:
        print("  backend Admin SDK         -> MISSING")
        print(f"    Add: backend/firebase-service-account-safe-hair-274.json")
        ok = False

    print()
    if ok:
        print("All parts aligned on safe-hair-274.")
        return 0
    print("Fix mismatches before demo / FYP testing.")
    return 1


if __name__ == "__main__":
    sys.path.insert(0, str(_BACKEND))
    raise SystemExit(main())
