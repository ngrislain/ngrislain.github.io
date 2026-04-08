"""Convert Verso blog HTML to platform-ready formats.

Reads generated post HTML, renders math to images, replaces iframes
with screenshots, and outputs clean HTML (for Medium/Substack) or
Markdown with KaTeX liquid tags (for Dev.to).
"""

import hashlib
import re
from dataclasses import dataclass, field
from pathlib import Path
from urllib.parse import quote

from bs4 import BeautifulSoup, Tag

SITE_BASE = "https://ngrislain.github.io"


@dataclass
class PostData:
    slug: str
    title: str
    date: str
    canonical_url: str
    content_html: str
    content_hash: str
    tags: list[str] = field(default_factory=list)


# --------------- math rendering ---------------

CODECOGS_BASE = "https://latex.codecogs.com/svg.image"


def _codecogs_url(latex: str, display: bool) -> str:
    """Build a codecogs.com URL that renders LaTeX to SVG."""
    prefix = "" if display else r"\inline "
    return f"{CODECOGS_BASE}?{quote(prefix + latex)}"


def math_to_images(soup: BeautifulSoup) -> BeautifulSoup:
    """Replace <code class='math inline/display'> with <img> from codecogs SVG API."""
    for el in soup.select("code.math.inline, code.math.display"):
        latex = el.get_text()
        display = "display" in el.get("class", [])
        url = _codecogs_url(latex, display)

        img = soup.new_tag("img", src=url, alt=latex)
        if display:
            p = soup.new_tag("p")
            p.append(img)
            el.replace_with(p)
        else:
            el.replace_with(img)

    return soup


def math_to_katex_liquid(text: str) -> str:
    """For Dev.to: replace math code elements with KaTeX liquid tags."""
    # Display math
    text = re.sub(
        r'<code class="math display">(.*?)</code>',
        r"{% katex %}\1{% endkatex %}",
        text,
        flags=re.DOTALL,
    )
    # Inline math
    text = re.sub(
        r'<code class="math inline">(.*?)</code>',
        r"{% katex inline %}\1{% endkatex %}",
        text,
        flags=re.DOTALL,
    )
    return text


# --------------- iframe handling ---------------

IFRAME_SCREENSHOTS = {
    "signature-method/signature-explorer.html": "signature-method/thumbnail.png",
    "prefix-scan/blelloch.html": "prefix-scan/blelloch-screenshot.png",
    "prefix-scan/blelloch-strings.html": "prefix-scan/blelloch-screenshot.png",
}


def replace_iframes(soup: BeautifulSoup) -> BeautifulSoup:
    """Replace <iframe> with screenshot image + 'Try it live' link."""
    for iframe in soup.select("iframe"):
        src = iframe.get("src", "")
        # Find a matching screenshot
        screenshot = None
        for pattern, img_path in IFRAME_SCREENSHOTS.items():
            if pattern in src:
                screenshot = f"{SITE_BASE}/static/blog/{img_path}"
                break

        live_url = f"{SITE_BASE}/{src}" if not src.startswith("http") else src

        fig = soup.new_tag("figure")
        if screenshot:
            img = soup.new_tag("img", src=screenshot, alt="Interactive visualization")
            fig.append(img)
        caption = soup.new_tag("figcaption")
        link = soup.new_tag("a", href=live_url)
        link.string = "Try the interactive version on the original post"
        caption.append(link)
        fig.append(caption)
        iframe.replace_with(fig)

    return soup


# --------------- HTML cleanup ---------------

STRIP_SELECTORS = [
    "script",
    "style",
    ".hero-image",
    ".share-section",
    "#share-buttons",
    ".post-header",  # We add title separately
]

MEDIUM_ALLOWED_TAGS = {
    "h3", "h4", "p", "strong", "em", "a", "pre", "code",
    "blockquote", "ul", "ol", "li", "img", "figure", "figcaption",
    "hr", "br", "table", "thead", "tbody", "tr", "th", "td",
}


def clean_html(soup: BeautifulSoup) -> BeautifulSoup:
    """Remove scripts, styles, and theme-specific elements."""
    for selector in STRIP_SELECTORS:
        for el in soup.select(selector):
            el.decompose()
    return soup


def absolutize_urls(soup: BeautifulSoup) -> BeautifulSoup:
    """Make all image src and link href absolute."""
    for img in soup.select("img"):
        src = img.get("src", "")
        if src and not src.startswith("http") and not src.startswith("data:"):
            img["src"] = f"{SITE_BASE}/{src}"
    for a in soup.select("a"):
        href = a.get("href", "")
        if href and not href.startswith("http") and not href.startswith("#") and not href.startswith("mailto:"):
            a["href"] = f"{SITE_BASE}/{href}"
    return soup


def downshift_headings(soup: BeautifulSoup) -> BeautifulSoup:
    """Convert h1->h3, h2->h4 for Medium compatibility."""
    for level in [2, 1]:
        for h in soup.select(f"h{level}"):
            h.name = f"h{level + 2}"
    return soup


def sanitize_for_medium(soup: BeautifulSoup) -> str:
    """Strip tags not in Medium's allowed set, keep their text content."""
    for tag in soup.find_all(True):
        if tag.name not in MEDIUM_ALLOWED_TAGS:
            tag.unwrap()
    # Remove all attributes except href, src, alt
    for tag in soup.find_all(True):
        allowed_attrs = {}
        for attr in ["href", "src", "alt"]:
            if tag.get(attr):
                allowed_attrs[attr] = tag[attr]
        tag.attrs = allowed_attrs
    return str(soup)


# --------------- main conversion ---------------

def discover_posts(build_dir: Path) -> list[dict]:
    """Find all post directories in build/blog/ and build/projects/."""
    posts = []
    for section in ["blog", "projects"]:
        section_dir = build_dir / section
        if not section_dir.exists():
            continue
        for entry in sorted(section_dir.iterdir()):
            index = entry / "index.html"
            if entry.is_dir() and index.exists() and entry.name != "index.html":
                # Skip the section landing page
                if entry.name.startswith("20"):  # Date-prefixed dirs
                    posts.append({
                        "section": section,
                        "slug": f"{section}/{entry.name}",
                        "path": index,
                    })
    return posts


def parse_post(post_info: dict) -> PostData | None:
    """Parse a generated post HTML file into PostData."""
    html = post_info["path"].read_text(encoding="utf-8")
    soup = BeautifulSoup(html, "html.parser")

    title_el = soup.select_one("h1.post-title")
    if not title_el:
        return None
    title = title_el.get_text(strip=True)

    date_el = soup.select_one(".post-meta")
    date = date_el.get_text(strip=True) if date_el else ""

    content_el = soup.select_one(".post-content")
    if not content_el:
        return None

    content_hash = hashlib.sha256(str(content_el).encode()).hexdigest()[:16]
    canonical_url = f"{SITE_BASE}/{post_info['slug']}/"

    return PostData(
        slug=post_info["slug"],
        title=title,
        date=date,
        canonical_url=canonical_url,
        content_html=str(content_el),
        content_hash=content_hash,
    )


def convert_for_medium(post: PostData) -> str:
    """Convert post to Medium-compatible HTML."""
    soup = BeautifulSoup(post.content_html, "html.parser")
    soup = clean_html(soup)
    soup = math_to_images(soup)
    soup = replace_iframes(soup)
    soup = absolutize_urls(soup)
    soup = downshift_headings(soup)
    html = sanitize_for_medium(soup)
    # Prepend canonical notice
    notice = f'<p><em>Originally published at <a href="{post.canonical_url}">{post.canonical_url}</a></em></p><hr>'
    return notice + html


def convert_for_devto(post: PostData) -> str:
    """Convert post to Dev.to Markdown with KaTeX liquid tags."""
    import html2text

    soup = BeautifulSoup(post.content_html, "html.parser")
    soup = clean_html(soup)
    soup = replace_iframes(soup)
    soup = absolutize_urls(soup)

    # Convert math before html2text conversion
    content = math_to_katex_liquid(str(soup))

    h = html2text.HTML2Text()
    h.body_width = 0  # No wrapping
    h.protect_links = True
    h.wrap_links = False
    markdown = h.handle(content)

    frontmatter = (
        f"---\n"
        f"title: \"{post.title}\"\n"
        f"published: false\n"
        f"canonical_url: {post.canonical_url}\n"
        f"tags: machinelearning, math, datascience\n"
        f"---\n\n"
    )
    return frontmatter + markdown


def convert_for_substack(post: PostData) -> str:
    """Convert post to Substack-compatible HTML."""
    # Substack accepts similar HTML to Medium
    return convert_for_medium(post)
