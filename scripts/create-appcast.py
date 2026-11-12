#!/usr/bin/env python3
"""Create one architecture's Sparkle feed from an already signed release archive."""
import argparse
import base64
import datetime
import html
import re
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import quote

SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', SPARKLE)


def release_notes_html(markdown):
    """Render our release-note headings, paragraphs and bullets as safe inline HTML."""
    blocks, paragraph, bullets = [], [], []

    def flush():
        if paragraph:
            blocks.append('<p>' + ' '.join(paragraph) + '</p>')
            paragraph.clear()
        if bullets:
            blocks.append('<ul>' + ''.join('<li>' + line + '</li>' for line in bullets) + '</ul>')
            bullets.clear()

    for line in markdown.splitlines():
        line = line.strip()
        if not line:
            flush()
        elif line.startswith('# '):
            flush()
            blocks.append('<h2>' + html.escape(line[2:]) + '</h2>')
        elif line.startswith('- '):
            if paragraph:
                flush()
            bullets.append(html.escape(line[2:]))
        else:
            if bullets:
                flush()
            paragraph.append(html.escape(line))
    flush()
    return '\n'.join(blocks)


def appcast(repository, tag, version, build, archive, signature, notes=''):
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
        raise ValueError('Invalid repository')
    if not re.fullmatch(r'v\d+\.\d+\.\d+', tag) or tag != 'v' + version:
        raise ValueError('Use a stable vMAJOR.MINOR.PATCH tag')
    if not str(build).isdigit() or int(build) <= 1:
        raise ValueError('Build must increase beyond the initial build 1')
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError('Invalid Ed25519 signature')
    if not archive.is_file() or archive.stat().st_size == 0:
        raise ValueError('Archive is missing or empty')
    root = ET.Element('rss', version='2.0')
    channel = ET.SubElement(root, 'channel')
    ET.SubElement(channel, 'title').text = 'Ares Updates'
    ET.SubElement(channel, 'link').text = f'https://github.com/{repository}/releases'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = f'Ares {version}'
    ET.SubElement(item, 'pubDate').text = datetime.datetime.now(datetime.timezone.utc).strftime('%a, %d %b %Y %H:%M:%S %z')
    ET.SubElement(item, f'{{{SPARKLE}}}version').text = str(build)
    ET.SubElement(item, f'{{{SPARKLE}}}shortVersionString').text = version
    ET.SubElement(item, f'{{{SPARKLE}}}minimumSystemVersion').text = '14.0'
    ET.SubElement(item, 'description').text = release_notes_html(notes) if notes.strip() else f'Ares {version}'
    ET.SubElement(item, 'enclosure', {
        'url': f'https://github.com/{repository}/releases/download/{quote(tag, safe="")}/{quote(archive.name, safe="")}',
        'length': str(archive.stat().st_size),
        'type': 'application/octet-stream',
        f'{{{SPARKLE}}}edSignature': signature,
    })
    ET.indent(root)
    return ET.tostring(root, encoding='utf-8', xml_declaration=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    for flag in ['repository', 'tag', 'version', 'build', 'archive', 'signature-file', 'output']:
        parser.add_argument('--' + flag, required=True)
    parser.add_argument('--notes-file')
    args = parser.parse_args()
    output = appcast(args.repository, args.tag, args.version, args.build, Path(args.archive),
                     Path(args.signature_file).read_text().strip(),
                     Path(args.notes_file).read_text() if args.notes_file else '')
    Path(args.output).write_bytes(output)
