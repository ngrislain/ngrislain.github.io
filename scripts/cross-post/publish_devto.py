"""Publish posts to Dev.to as drafts via the Forem API."""

import requests

API_BASE = "https://dev.to/api"


class DevtoPublisher:
    def __init__(self, api_key: str):
        self.session = requests.Session()
        self.session.headers.update({
            "api-key": api_key,
            "Content-Type": "application/json",
        })

    def create_draft(
        self,
        title: str,
        body_markdown: str,
        canonical_url: str,
        tags: list[str] | None = None,
    ) -> dict:
        payload = {
            "article": {
                "title": title,
                "body_markdown": body_markdown,
                "canonical_url": canonical_url,
                "published": False,
            }
        }
        if tags:
            payload["article"]["tags"] = tags[:4]  # Dev.to max 4 tags

        resp = self.session.post(f"{API_BASE}/articles", json=payload)
        resp.raise_for_status()
        return resp.json()
