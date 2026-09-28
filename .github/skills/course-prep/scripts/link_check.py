"""Course-prep link & video checker.

Verifies every URL destined for a course README/docs:
  * regular URLs  -> HTTP status, final URL after redirects, and <title>
  * YouTube URLs  -> YouTube oEmbed (title + author_name + author_url), which
                     doubles as a liveness check (oEmbed 404 == unavailable)

This supports the two Phase-2 quality gates:
  1. Links are verified *semantically* (status + final URL + title), not just 200.
  2. Videos are confirmed LIVE and on an OFFICIAL Microsoft channel.

Usage:
    python link_check.py urls.txt

Input file: one entry per line, either "label | url" or just "url".
Blank lines and lines starting with '#' are ignored.

Notes:
  * Prints UTF-8 (so localized zh-tw/zh-cn titles render on any console).
  * A 200 that redirects to a generic hub/browse page (e.g. .../training/browse/)
    means the specific page no longer exists -- treat as NOT FOUND and drop it.
  * Known-good redirects: aka.ms short links, GitHub archive -> codeload,
    and the learn.microsoft.com "/copilot/microsoft-365/" -> "/microsoft-365/copilot/"
    move. Keep the *final* URL in the README.
  * oEmbed returns 403 (not 404) when a video exists but has embedding disabled;
    you then cannot confirm the channel automatically -- verify by hand or drop.
"""
import sys
import re
import json
import urllib.request
import urllib.error

UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")
TITLE_RE = re.compile(r"<title[^>]*>(.*?)</title>", re.I | re.S)

# Official Microsoft YouTube channels seen across course decks. Extend as needed.
# oEmbed returns author_name (display) and author_url (channel handle URL).
OFFICIAL_CHANNELS = {
    "Microsoft", "Microsoft 365", "Microsoft Learn", "Microsoft Mechanics",
    "Microsoft Developer", "Microsoft 365 Developer", "Microsoft Azure",
    "Microsoft Community Learning", "Microsoft Cloud", "Microsoft Security",
    "Microsoft Copilot", "Microsoft Power Platform", "Microsoft SharePoint",
    "Microsoft APAC", "MicrosoftANZ",
}


def fetch(url, timeout=25):
    req = urllib.request.Request(
        url, headers={"User-Agent": UA, "Accept-Language": "en-US,en;q=0.9"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.geturl(), r.read(200000).decode("utf-8", "ignore")
    except urllib.error.HTTPError as e:
        return e.code, url, ""
    except Exception as e:  # noqa: BLE001
        return f"ERR:{type(e).__name__}", url, ""


def yt_id(url):
    m = re.search(r"(?:youtu\.be/|v=|/embed/)([A-Za-z0-9_-]{11})", url)
    return m.group(1) if m else None


def oembed(vid):
    status, _, body = fetch(
        f"https://www.youtube.com/oembed?url=https://youtu.be/{vid}&format=json")
    if status == 200 and body:
        try:
            d = json.loads(body)
            author = d.get("author_name", "")
            official = "OFFICIAL" if author in OFFICIAL_CHANNELS else "!!CHECK-CHANNEL!!"
            return f"LIVE | {official} | {author} | {d.get('title')}"
        except Exception:  # noqa: BLE001
            return "LIVE | (parse error)"
    return f"DEAD/UNAVAILABLE (oEmbed status={status})"


def title_of(body):
    m = TITLE_RE.search(body)
    return re.sub(r"\s+", " ", m.group(1)).strip()[:110] if m else ""


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:  # noqa: BLE001
        pass
    with open(sys.argv[1], encoding="utf-8") as f:
        lines = [ln.strip() for ln in f
                 if ln.strip() and not ln.strip().startswith("#")]
    for ln in lines:
        label, url = ([x.strip() for x in ln.split("|", 1)]
                      if "|" in ln else ("", ln))
        vid = yt_id(url)
        if vid:
            print(f"[VIDEO] {label or vid}: {oembed(vid)}")
            continue
        status, final, body = fetch(url)
        redir = "" if final == url else f"  ->FINAL: {final}"
        print(f"[{status}] {label or url}")
        print(f"    url: {url}{redir}")
        print(f"    title: {title_of(body)}")


if __name__ == "__main__":
    main()
