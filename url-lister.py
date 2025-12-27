#!/usr/bin/env python3
"""
Generic playlist URL scraper
Works on ANY public playlist page (HTML-based)

- Intelligent URL detection
- Handles relative URLs
- Extracts from anchors, iframes, and JS blobs
- Outputs one URL per line
"""

import re
import sys
import requests
from bs4 import BeautifulSoup
from urllib.parse import urljoin, urlparse

# Keywords commonly found in video URLs
VIDEO_KEYWORDS = [
    "watch", "video", "videos", "playlist",
    "play", "embed", "media", "stream"
]

def looks_like_video_url(url):
    parsed = urlparse(url)
    if not parsed.scheme.startswith("http"):
        return False

    path = parsed.path.lower()
    query = parsed.query.lower()

    return any(k in path or k in query for k in VIDEO_KEYWORDS)

def extract_urls(html, base_url):
    soup = BeautifulSoup(html, "lxml")
    found = set()

    # 1. Extract <a href="">
    for tag in soup.find_all("a", href=True):
        full_url = urljoin(base_url, tag["href"])
        if looks_like_video_url(full_url):
            found.add(full_url)

    # 2. Extract <iframe src="">
    for tag in soup.find_all("iframe", src=True):
        full_url = urljoin(base_url, tag["src"])
        found.add(full_url)

    # 3. Extract URLs from inline JS / text blobs
    raw_urls = re.findall(
        r'https?://[^\s"\'>]+',
        html
    )

    for url in raw_urls:
        if looks_like_video_url(url):
            found.add(url)

    return sorted(found)

def main():
    if len(sys.argv) != 3:
        print("Usage:")
        print("  python3 playlist_url_scraper.py <playlist_url> <output.txt>")
        sys.exit(1)

    playlist_url = sys.argv[1]
    output_file = sys.argv[2]

    headers = {
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64)"
    }

    try:
        response = requests.get(playlist_url, headers=headers, timeout=15)
        response.raise_for_status()
    except Exception as e:
        print(f"Error fetching URL: {e}")
        sys.exit(1)

    urls = extract_urls(response.text, playlist_url)

    if not urls:
        print("No video URLs found.")
        sys.exit(1)

    with open(output_file, "w") as f:
        for url in urls:
            f.write(url + "\n")

    print(f"[+] Found {len(urls)} video-related URLs")
    print(f"[+] Saved to {output_file}")

if __name__ == "__main__":
    main()
