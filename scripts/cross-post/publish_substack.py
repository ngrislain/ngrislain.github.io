"""Publish posts to Substack as drafts via the unofficial substack-api library.

This is fragile: authentication uses browser cookies that expire.
If auth fails, publishing is skipped with a warning.
"""

import logging

logger = logging.getLogger(__name__)


class SubstackPublisher:
    def __init__(self, publication_url: str, email: str, password: str):
        self.publication_url = publication_url
        self.email = email
        self.password = password
        self._api = None

    def _connect(self):
        try:
            from substack_api import Api
            self._api = Api(
                email=self.email,
                password=self.password,
                publication_url=self.publication_url,
            )
        except Exception as e:
            logger.warning(f"Substack auth failed (cookies may have expired): {e}")
            self._api = None

    def create_draft(
        self,
        title: str,
        content_html: str,
        subtitle: str = "",
    ) -> dict | None:
        if self._api is None:
            self._connect()
        if self._api is None:
            logger.warning("Skipping Substack: not authenticated")
            return None

        try:
            draft = self._api.post_draft(
                title=title,
                subtitle=subtitle,
            )
            draft_id = draft.get("id")
            if draft_id:
                # Update draft body with HTML content
                self._api.put_draft(
                    draft_id=draft_id,
                    body_html=content_html,
                )
            return draft
        except Exception as e:
            logger.warning(f"Substack publish failed: {e}")
            return None
