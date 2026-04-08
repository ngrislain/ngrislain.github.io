#!/usr/bin/env python3
"""Cross-post blog articles to Medium, Dev.to, and Substack.

Usage:
    python main.py --build-dir ../../build --platforms medium,devto,substack
    python main.py --build-dir ../../build --dry-run
    python main.py --build-dir ../../build --post blog/2026-4-6-... --platforms devto --dry-run
"""

import argparse
import json
import logging
import os
import sys
from pathlib import Path

from convert import (
    convert_for_devto,
    convert_for_medium,
    convert_for_substack,
    discover_posts,
    parse_post,
)

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)

STATE_FILE = Path(__file__).resolve().parent.parent.parent / "cross-post-state.json"
SCRIPT_DIR = Path(__file__).resolve().parent


def load_state() -> dict:
    if STATE_FILE.exists():
        return json.loads(STATE_FILE.read_text())
    return {"posts": {}}


def save_state(state: dict):
    STATE_FILE.write_text(json.dumps(state, indent=2) + "\n")


def publish_to_medium(post, content_html: str, state: dict) -> bool:
    token = os.environ.get("MEDIUM_TOKEN")
    if not token:
        logger.warning("MEDIUM_TOKEN not set, skipping Medium")
        return False

    from publish_medium import MediumPublisher

    pub = MediumPublisher(token)
    result = pub.create_draft(
        title=post.title,
        content_html=content_html,
        canonical_url=post.canonical_url,
        tags=post.tags or ["machine-learning", "mathematics"],
    )
    state["posts"].setdefault(post.slug, {})["medium_url"] = result.get("url", "")
    logger.info(f"  Medium draft: {result.get('url', 'created')}")
    return True


def publish_to_devto(post, body_markdown: str, state: dict) -> bool:
    api_key = os.environ.get("DEVTO_API_KEY")
    if not api_key:
        logger.warning("DEVTO_API_KEY not set, skipping Dev.to")
        return False

    from publish_devto import DevtoPublisher

    pub = DevtoPublisher(api_key)
    result = pub.create_draft(
        title=post.title,
        body_markdown=body_markdown,
        canonical_url=post.canonical_url,
        tags=post.tags or ["machinelearning", "math", "datascience"],
    )
    state["posts"].setdefault(post.slug, {})["devto_id"] = result.get("id", 0)
    logger.info(f"  Dev.to draft: https://dev.to/dashboard (id={result.get('id')})")
    return True


def publish_to_substack(post, content_html: str, state: dict) -> bool:
    pub_url = os.environ.get("SUBSTACK_URL")
    email = os.environ.get("SUBSTACK_EMAIL")
    password = os.environ.get("SUBSTACK_PASSWORD")
    if not all([pub_url, email, password]):
        logger.warning("Substack credentials not set, skipping Substack")
        return False

    from publish_substack import SubstackPublisher

    pub = SubstackPublisher(pub_url, email, password)
    result = pub.create_draft(
        title=post.title,
        content_html=content_html,
    )
    if result:
        state["posts"].setdefault(post.slug, {})["substack_id"] = result.get("id", "")
        logger.info(f"  Substack draft created")
        return True
    return False


def main():
    parser = argparse.ArgumentParser(description="Cross-post blog to external platforms")
    parser.add_argument("--build-dir", required=True, help="Path to build/ directory")
    parser.add_argument("--platforms", default="medium,devto,substack",
                        help="Comma-separated list of platforms")
    parser.add_argument("--post", help="Publish only this specific post slug")
    parser.add_argument("--dry-run", action="store_true",
                        help="Convert but do not publish; write output to dry-run/")
    parser.add_argument("--force", action="store_true",
                        help="Publish even if already in state file")
    args = parser.parse_args()

    build_dir = Path(args.build_dir).resolve()
    if not build_dir.exists():
        logger.error(f"Build directory not found: {build_dir}")
        sys.exit(1)

    platforms = set(args.platforms.split(","))
    state = load_state()

    # Discover posts
    all_posts = discover_posts(build_dir)
    if args.post:
        all_posts = [p for p in all_posts if args.post in p["slug"]]

    if not all_posts:
        logger.info("No posts found")
        return

    logger.info(f"Found {len(all_posts)} post(s)")
    changed = False

    for post_info in all_posts:
        post = parse_post(post_info)
        if not post:
            logger.warning(f"  Could not parse: {post_info['slug']}")
            continue

        # Check if already published with same content
        existing = state["posts"].get(post.slug, {})
        if existing.get("content_hash") == post.content_hash and not args.force:
            logger.info(f"  Skipping (unchanged): {post.title}")
            continue

        logger.info(f"  Processing: {post.title}")

        if args.dry_run:
            dry_dir = Path("dry-run") / post.slug.replace("/", "_")
            dry_dir.mkdir(parents=True, exist_ok=True)

            if "medium" in platforms:
                html = convert_for_medium(post)
                (dry_dir / "medium.html").write_text(html, encoding="utf-8")
                logger.info(f"    Wrote {dry_dir}/medium.html")

            if "devto" in platforms:
                md = convert_for_devto(post)
                (dry_dir / "devto.md").write_text(md, encoding="utf-8")
                logger.info(f"    Wrote {dry_dir}/devto.md")

            if "substack" in platforms:
                html = convert_for_substack(post)
                (dry_dir / "substack.html").write_text(html, encoding="utf-8")
                logger.info(f"    Wrote {dry_dir}/substack.html")

            continue

        # Publish to each platform
        if "medium" in platforms:
            try:
                publish_to_medium(
                    post, convert_for_medium(post), state
                )
            except Exception as e:
                logger.error(f"  Medium failed: {e}")

        if "devto" in platforms:
            try:
                publish_to_devto(post, convert_for_devto(post), state)
            except Exception as e:
                logger.error(f"  Dev.to failed: {e}")

        if "substack" in platforms:
            try:
                publish_to_substack(
                    post, convert_for_substack(post), state
                )
            except Exception as e:
                logger.error(f"  Substack failed: {e}")

        # Update state
        state["posts"].setdefault(post.slug, {})["content_hash"] = post.content_hash
        changed = True

    if changed and not args.dry_run:
        save_state(state)
        logger.info(f"State saved to {STATE_FILE}")


if __name__ == "__main__":
    main()
