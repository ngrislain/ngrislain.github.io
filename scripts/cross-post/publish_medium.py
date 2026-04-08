"""Publish posts to Medium as drafts via the Medium API."""

import requests

API_BASE = "https://api.medium.com/v1"


class MediumPublisher:
    def __init__(self, token: str):
        self.token = token
        self.session = requests.Session()
        self.session.headers.update({
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        })
        self.user_id = None

    def get_user(self) -> dict:
        resp = self.session.get(f"{API_BASE}/me")
        resp.raise_for_status()
        data = resp.json()["data"]
        self.user_id = data["id"]
        return data

    def create_draft(
        self,
        title: str,
        content_html: str,
        canonical_url: str,
        tags: list[str] | None = None,
    ) -> dict:
        if not self.user_id:
            self.get_user()

        payload = {
            "title": title,
            "contentFormat": "html",
            "content": content_html,
            "canonicalUrl": canonical_url,
            "publishStatus": "draft",
        }
        if tags:
            payload["tags"] = tags[:3]  # Medium max 3 tags

        resp = self.session.post(
            f"{API_BASE}/users/{self.user_id}/posts",
            json=payload,
        )
        resp.raise_for_status()
        return resp.json()["data"]
