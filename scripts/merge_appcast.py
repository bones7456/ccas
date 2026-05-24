#!/usr/bin/env python3
"""Insert a Sparkle appcast <item> snippet into an existing appcast.xml.

If an item for the same sparkle:shortVersionString already exists, replace it.
Items are kept ordered newest-first by pubDate.

Usage: merge_appcast.py <appcast.xml> <item.xml>
"""
from __future__ import annotations

import re
import sys
from email.utils import parsedate_to_datetime
from xml.etree import ElementTree as ET

NS = {
    "sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle",
    "dc": "http://purl.org/dc/elements/1.1/",
}
for prefix, uri in NS.items():
    ET.register_namespace(prefix, uri)


def short_version(item: ET.Element) -> str | None:
    el = item.find("sparkle:shortVersionString", NS)
    return el.text.strip() if el is not None and el.text else None


def pub_date_key(item: ET.Element):
    el = item.find("pubDate")
    if el is None or not el.text:
        return None
    try:
        return parsedate_to_datetime(el.text.strip())
    except (TypeError, ValueError):
        return None


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    appcast_path, item_path = sys.argv[1], sys.argv[2]

    tree = ET.parse(appcast_path)
    channel = tree.getroot().find("channel")
    if channel is None:
        print(f"error: no <channel> in {appcast_path}", file=sys.stderr)
        return 1

    new_item = ET.parse(item_path).getroot()
    if new_item.tag != "item":
        print(f"error: {item_path} root must be <item>, got {new_item.tag}", file=sys.stderr)
        return 1
    new_version = short_version(new_item)
    if not new_version:
        print("error: new item is missing sparkle:shortVersionString", file=sys.stderr)
        return 1

    # Drop any existing item with the same shortVersionString so re-runs of the
    # same release are idempotent.
    for existing in list(channel.findall("item")):
        if short_version(existing) == new_version:
            channel.remove(existing)

    items = list(channel.findall("item"))
    for item in items:
        channel.remove(item)
    items.append(new_item)
    items.sort(key=lambda i: pub_date_key(i) or 0, reverse=True)
    for item in items:
        channel.append(item)

    ET.indent(tree, space="    ")
    tree.write(appcast_path, encoding="utf-8", xml_declaration=True)
    # ET writes <?xml version='1.0' ...?>; normalize to double-quotes for nicer diffs.
    with open(appcast_path, "rb") as fh:
        data = fh.read()
    data = data.replace(b"<?xml version='1.0' encoding='utf-8'?>", b'<?xml version="1.0" encoding="utf-8"?>', 1)
    with open(appcast_path, "wb") as fh:
        fh.write(data)
    return 0


if __name__ == "__main__":
    sys.exit(main())
