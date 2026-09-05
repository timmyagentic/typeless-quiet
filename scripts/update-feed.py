#!/usr/bin/env python3
"""Prepare a reviewed Sparkle feed from final signed/notarized public artifacts."""
import argparse
import base64
import contextlib
import datetime
import hashlib
import pathlib
import plistlib
import re
import subprocess
import tempfile
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUNDLE_ID = 'io.github.timmyagentic.TypelessQuiet'
REPOSITORY = 'https://github.com/timmyagentic/typeless-plusplus'
FEED_URL = 'https://raw.githubusercontent.com/timmyagentic/typeless-plusplus/main/appcast.xml'
ACCOUNT = 'typeless-plusplus'
BIN = ROOT / '.build/artifacts/sparkle/Sparkle/bin'
NAMESPACE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
S = '{' + NAMESPACE + '}'
ET.register_namespace('sparkle', NAMESPACE)


def require_base64(value, length):
    try:
        if len(base64.b64decode(value, validate=True)) == length:
            return
    except (ValueError, TypeError):
        pass
    raise ValueError('Invalid public key or signature encoding')


def build_number(value):
    if not isinstance(value, str) or not re.fullmatch(r'[1-9][0-9]*', value):
        raise ValueError('Build must be a positive integer')
    return int(value)


def validate_metadata(info):
    if info.get('CFBundleIdentifier') != BUNDLE_ID:
        raise ValueError('Unexpected app identity')
    build_number(info.get('CFBundleVersion'))
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', info.get('CFBundleShortVersionString', '')):
        raise ValueError('Invalid marketing version')
    if info.get('TypelessUpdateChannel') not in ('stable', 'beta'):
        raise ValueError('Invalid bundled update channel')
    require_base64(info.get('SUPublicEDKey'), 32)


def empty_feed():
    root = ET.Element('rss', {'version': '2.0'})
    channel = ET.SubElement(root, 'channel')
    ET.SubElement(channel, 'title').text = 'Typeless++ Updates'
    ET.SubElement(channel, 'link').text = REPOSITORY
    ET.SubElement(channel, 'description').text = 'Typeless++ stable and opt-in beta updates'
    ET.SubElement(channel, 'language').text = 'zh-CN'
    return ET.ElementTree(root)


def make_item(info, tag, filename, signature, length):
    validate_metadata(info)
    version = info['CFBundleShortVersionString']
    suffix = r'-beta\.[1-9][0-9]*' if info['TypelessUpdateChannel'] == 'beta' else ''
    if not re.fullmatch('v' + re.escape(version) + suffix, tag):
        raise ValueError('Tag, marketing version and bundled channel do not agree')
    if not re.fullmatch(r'[A-Za-z0-9+_.-]+\.(zip|dmg)', filename) or '..' in filename:
        raise ValueError('Invalid archive filename')
    require_base64(signature, 64)
    if length <= 0:
        raise ValueError('Archive must not be empty')
    item = ET.Element('item')
    ET.SubElement(item, 'title').text = 'Typeless++ ' + tag.removeprefix('v')
    ET.SubElement(item, 'link').text = REPOSITORY + '/releases/tag/' + tag
    ET.SubElement(item, 'pubDate').text = datetime.datetime.now(datetime.timezone.utc).strftime('%a, %d %b %Y %H:%M:%S +0000')
    ET.SubElement(item, S + 'version').text = info['CFBundleVersion']
    ET.SubElement(item, S + 'shortVersionString').text = tag.removeprefix('v')
    ET.SubElement(item, S + 'minimumSystemVersion').text = info.get('LSMinimumSystemVersion', '13.0')
    if info['TypelessUpdateChannel'] == 'beta':
        ET.SubElement(item, S + 'channel').text = 'beta'
    ET.SubElement(item, 'enclosure', {
        'url': REPOSITORY + '/releases/download/' + tag + '/' + filename,
        'length': str(length), 'type': 'application/octet-stream', S + 'edSignature': signature,
    })
    return item


def validate_feed(tree):
    root = tree.getroot()
    channel = root.find('channel')
    if root.tag != 'rss' or channel is None or len(root.findall('channel')) != 1:
        raise ValueError('Expected one RSS channel')
    builds = set()
    for item in channel.findall('item'):
        build = build_number(item.findtext(S + 'version'))
        if build in builds:
            raise ValueError('Duplicate build in feed')
        builds.add(build)
        if item.findtext(S + 'channel') not in (None, 'beta'):
            raise ValueError('Unknown update channel')
        enc = item.find('enclosure')
        if enc is None:
            raise ValueError('Missing archive enclosure')
        require_base64(enc.get(S + 'edSignature'), 64)
        build_number(enc.get('length'))
        url = enc.get('url', '')
        if not re.fullmatch(re.escape(REPOSITORY) + r'/releases/download/v[0-9]+\.[0-9]+\.[0-9]+(?:-beta\.[1-9][0-9]*)?/[A-Za-z0-9+_.-]+\.(zip|dmg)', url):
            raise ValueError('Archive URL must be a canonical public release asset')
        tag = url.split('/')[-2]
        if item.findtext(S + 'shortVersionString') != tag.removeprefix('v'):
            raise ValueError('Feed display version and release tag disagree')
        is_beta = '-beta.' in tag
        if is_beta != (item.findtext(S + 'channel') == 'beta'):
            raise ValueError('Release URL and feed channel disagree')


def append_item(tree, item):
    validate_feed(tree)
    channel = tree.getroot().find('channel')
    highest = max((build_number(i.findtext(S + 'version')) for i in channel.findall('item')), default=0)
    if build_number(item.findtext(S + 'version')) <= highest:
        raise ValueError('New build must exceed every existing Beta and Stable build')
    channel.insert(0, item)
    validate_feed(tree)


def run(*args):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True, text=True).stdout.strip()


@contextlib.contextmanager
def extracted_app(archive):
    with tempfile.TemporaryDirectory(prefix='typeless-update-') as temporary:
        location = pathlib.Path(temporary) / 'contents'
        location.mkdir()
        mounted = False
        try:
            if archive.suffix == '.zip':
                with zipfile.ZipFile(archive) as source:
                    for name in source.namelist():
                        if name.startswith('/') or '..' in pathlib.PurePosixPath(name).parts:
                            raise ValueError('Archive path escapes extraction directory')
                run('ditto', '-x', '-k', archive, location)
            elif archive.suffix == '.dmg':
                run('hdiutil', 'attach', archive, '-readonly', '-nobrowse', '-noautoopen', '-mountpoint', location)
                mounted = True
            else:
                raise ValueError('Only final ZIP and DMG archives are supported')
            apps = list(location.glob('*.app'))
            if len(apps) != 1 or apps[0].name != 'Typeless++.app':
                raise ValueError('Archive must contain exactly Typeless++.app')
            yield apps[0]
        finally:
            if mounted:
                run('hdiutil', 'detach', location)


def prepare(args):
    archive = args.archive.resolve()
    before = hashlib.sha256(archive.read_bytes()).digest()
    expected = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
    with extracted_app(archive) as app:
        info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        validate_metadata(info)
        if info['SUPublicEDKey'] != expected['SUPublicEDKey'] or info.get('SUFeedURL') != FEED_URL:
            raise ValueError('Artifact key/feed do not match this project')
        if info.get('TypelessUpdaterQA') or not (app / 'Contents/Frameworks/Sparkle.framework').is_dir():
            raise ValueError('QA or non-updatable app cannot be published in this feed')
        run('codesign', '--verify', '--deep', '--strict', app)
        run('xcrun', 'stapler', 'validate', app)
        run('spctl', '--assess', '--type', 'execute', '--verbose=2', app)
    public_key = run(BIN / 'generate_keys', '--account', ACCOUNT, '-p')
    if public_key != expected['SUPublicEDKey']:
        raise ValueError('Keychain signing key does not match the bundled public key')
    signature = run(BIN / 'sign_update', '--account', ACCOUNT, '-p', archive)
    run(BIN / 'sign_update', '--account', ACCOUNT, '--verify', archive, signature)
    if hashlib.sha256(archive.read_bytes()).digest() != before:
        raise ValueError('Archive changed during verification')
    tree = ET.parse(args.feed)
    append_item(tree, make_item(info, args.tag, archive.name, signature, archive.stat().st_size))
    ET.indent(tree, space='  ')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    tree.write(args.output, encoding='utf-8', xml_declaration=True)
    print('Prepared verified feed:', args.output)


def verify_public(args):
    expected = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
    if run(BIN / 'generate_keys', '--account', ACCOUNT, '-p') != expected['SUPublicEDKey']:
        raise ValueError('Keychain verification key does not match the bundled public key')
    tree = ET.parse(args.feed)
    validate_feed(tree)
    matches = [i for i in tree.getroot().findall('channel/item') if i.findtext(S + 'version') == args.build]
    if len(matches) != 1:
        raise ValueError('Expected one matching build')
    enc = matches[0].find('enclosure')
    with tempfile.TemporaryDirectory(prefix='typeless-public-update-') as temporary:
        archive = pathlib.Path(temporary) / pathlib.PurePosixPath(enc.get('url')).name
        with urllib.request.urlopen(enc.get('url'), timeout=60) as response, archive.open('wb') as output:
            if not response.url.startswith('https://'):
                raise ValueError('Insecure download redirect')
            downloaded = 0
            while chunk := response.read(1024 * 1024):
                downloaded += len(chunk)
                if downloaded > int(enc.get('length')):
                    raise ValueError('Public archive exceeds declared length')
                output.write(chunk)
        if archive.stat().st_size != int(enc.get('length')):
            raise ValueError('Public archive length differs from feed')
        run(BIN / 'sign_update', '--account', ACCOUNT, '--verify', archive, enc.get(S + 'edSignature'))
        print('Public archive length and Ed25519 signature verified')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    validate = commands.add_parser('validate')
    validate.add_argument('feed', type=pathlib.Path)
    create = commands.add_parser('prepare')
    create.add_argument('archive', type=pathlib.Path)
    create.add_argument('--tag', required=True)
    create.add_argument('--feed', type=pathlib.Path, default=ROOT / 'appcast.xml')
    create.add_argument('--output', type=pathlib.Path, required=True)
    public = commands.add_parser('verify-public')
    public.add_argument('feed', type=pathlib.Path)
    public.add_argument('--build', required=True)
    args = parser.parse_args()
    try:
        if args.command == 'prepare': prepare(args)
        elif args.command == 'verify-public': verify_public(args)
        else:
            validate_feed(ET.parse(args.feed))
            print('Feed schema, channels, versions and signature fields verified')
    except (ValueError, OSError, ET.ParseError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'Update feed verification failed: {error}\n')


if __name__ == '__main__': main()
