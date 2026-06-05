"""Deploy firebase/firestore.rules to project safe-hair-274 via Rules API."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import google.auth.transport.requests
import requests
from google.oauth2 import service_account

_ROOT = Path(__file__).resolve().parents[2]
_RULES_FILE = _ROOT / "firebase" / "firestore.rules"

sys.path.insert(0, str(_ROOT / "backend"))
from safe_hair_project import PROJECT_ID, resolve_service_account_path  # noqa: E402

RULES_API = "https://firebaserules.googleapis.com/v1"
SCOPES = ("https://www.googleapis.com/auth/cloud-platform",)


def _auth_session() -> tuple[requests.Session, str]:
    path = resolve_service_account_path()
    if not path:
        raise SystemExit(
            f"No service account JSON for {PROJECT_ID}. "
            "Add backend/firebase-service-account-safe-hair-274.json"
        )
    creds = service_account.Credentials.from_service_account_file(path, scopes=SCOPES)
    creds.refresh(google.auth.transport.requests.Request())
    session = requests.Session()
    session.headers["Authorization"] = f"Bearer {creds.token}"
    return session, PROJECT_ID


def deploy_rules(rules_text: str) -> str:
    session, project_id = _auth_session()
    project = f"projects/{project_id}"

    create_resp = session.post(
        f"{RULES_API}/{project}/rulesets",
        json={
            "source": {
                "files": [
                    {
                        "name": "firestore.rules",
                        "content": rules_text,
                    }
                ]
            }
        },
        timeout=60,
    )
    if not create_resp.ok:
        raise SystemExit(
            f"Create ruleset failed ({create_resp.status_code}): {create_resp.text}"
        )
    ruleset_name = create_resp.json()["name"]

    release_name = f"{project}/releases/cloud.firestore"
    patch_resp = session.patch(
        f"{RULES_API}/{release_name}",
        params={"updateMask": "rulesetName"},
        json={
            "release": {
                "name": release_name,
                "rulesetName": ruleset_name,
            }
        },
        timeout=60,
    )
    if not patch_resp.ok:
        raise SystemExit(
            f"Release rules failed ({patch_resp.status_code}): {patch_resp.text}"
        )
    return ruleset_name


def main() -> None:
    if not _RULES_FILE.is_file():
        raise SystemExit(f"Missing rules file: {_RULES_FILE}")
    rules_text = _RULES_FILE.read_text(encoding="utf-8")
    ruleset = deploy_rules(rules_text)
    print(f"Deployed Firestore rules to {PROJECT_ID}")
    print(f"Ruleset: {ruleset}")
    print(f"Source: {_RULES_FILE}")


if __name__ == "__main__":
    main()
