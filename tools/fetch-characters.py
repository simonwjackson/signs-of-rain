#!/usr/bin/env nix
#! nix shell nixpkgs#python3 --command python3
"""Fetch primary-source character assets. Downloads stay outside the repository."""

import argparse
import pathlib
import urllib.request
import urllib.parse
import http.cookiejar
import json
import re


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url")
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument(
        "--itch", action="store_true", help="Get the author's free download page"
    )
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    opener = urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar())
    )
    opener.addheaders = [("User-Agent", "Mozilla/5.0")]
    with opener.open(args.url, timeout=90) as response:
        payload = response.read()
    if args.itch:
        token = re.search(r'name="csrf_token" value="([^"]+)', payload.decode()).group(
            1
        )
        data = urllib.parse.urlencode({"csrf_token": token}).encode()
        request = urllib.request.Request(
            args.url.rstrip("/") + "/download_url",
            data=data,
            headers={"Referer": args.url, "X-Requested-With": "XMLHttpRequest"},
        )
        result = json.loads(opener.open(request, timeout=90).read())
        print(result)
        page = opener.open(result["url"], timeout=90).read().decode()
        (args.output.parent / (args.output.stem + "-download.html")).write_text(page)
        token = re.search(r'name="csrf_token" value="([^"]+)', page).group(1)
        upload_id = re.search(r'data-upload_id="([^"]+)', page).group(1)
        request = urllib.request.Request(
            args.url.rstrip("/") + "/file/" + upload_id,
            data=urllib.parse.urlencode({"csrf_token": token}).encode(),
            headers={"Referer": result["url"], "X-Requested-With": "XMLHttpRequest"},
        )
        download = json.loads(opener.open(request, timeout=90).read())
        print(download)
        payload = opener.open(download["url"], timeout=90).read()
    args.output.write_bytes(payload)
    print(f"Fetched {args.url} -> {args.output} ({args.output.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
