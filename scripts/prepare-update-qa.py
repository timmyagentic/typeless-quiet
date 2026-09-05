#!/usr/bin/env python3
"""Create isolated old/new apps and a local signed feed; never touches Applications."""
import argparse
import importlib.util
import json
import pathlib
import plistlib
import subprocess
import uuid
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent


def run(*args):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True, text=True).stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=pathlib.Path, default=ROOT / 'dist/Typeless++.app')
    parser.add_argument('--port', type=int, required=True)
    parser.add_argument('--identity', required=True)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('Use a new output directory for each isolated QA run')
    if not 1024 <= args.port <= 65535:
        parser.error('Use an unprivileged local port')
    args.output.mkdir(parents=True)
    identifier = 'io.github.timmyagentic.TypelessUpdaterQA.' + uuid.uuid4().hex
    feed_url = f'http://127.0.0.1:{args.port}/appcast.xml'
    apps = {}
    for label, build in [('installed', '1001'), ('candidate', '1002')]:
        app = args.output / label / 'Typeless++.app'
        run('ditto', args.app, app)
        info_path = app / 'Contents/Info.plist'
        info = plistlib.loads(info_path.read_bytes())
        info.update({'CFBundleIdentifier': identifier, 'CFBundleVersion': build,
                     'TypelessUpdaterQA': True, 'SUFeedURL': feed_url,
                     'SUEnableAutomaticChecks': True, 'SUAutomaticallyUpdate': False,
                     'NSAppTransportSecurity': {'NSAllowsLocalNetworking': True}})
        info_path.write_bytes(plistlib.dumps(info, sort_keys=False))
        run('codesign', '--force', '--options', 'runtime', '--timestamp', '--sign', args.identity, app)
        run('codesign', '--verify', '--deep', '--strict', app)
        apps[label] = str(app)
    server = args.output / 'server'
    server.mkdir()
    archive = server / 'TypelessPlusPlus-qa.zip'
    run('ditto', '-c', '-k', '--keepParent', apps['candidate'], archive)
    signer = ROOT / '.build/artifacts/sparkle/Sparkle/bin/sign_update'
    signature = run(signer, '--account', 'typeless-plusplus', '-p', archive)
    run(signer, '--account', 'typeless-plusplus', '--verify', archive, signature)
    spec = importlib.util.spec_from_file_location('update_feed', ROOT / 'scripts/update-feed.py')
    feed = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(feed)
    tree = feed.empty_feed()
    item = ET.SubElement(tree.getroot().find('channel'), 'item')
    ET.SubElement(item, 'title').text = 'Typeless++ QA 1002'
    ET.SubElement(item, feed.S + 'version').text = '1002'
    ET.SubElement(item, feed.S + 'shortVersionString').text = '0.0.1 QA 1002'
    ET.SubElement(item, feed.S + 'minimumSystemVersion').text = '13.0'
    ET.SubElement(item, feed.S + 'channel').text = 'beta'
    ET.SubElement(item, 'enclosure', {'url': f'http://127.0.0.1:{args.port}/' + archive.name,
                  'length': str(archive.stat().st_size), 'type': 'application/octet-stream',
                  feed.S + 'edSignature': signature})
    ET.indent(tree, space='  ')
    tree.write(server / 'appcast.xml', encoding='utf-8', xml_declaration=True)
    feed.empty_feed().write(server / 'empty.xml', encoding='utf-8', xml_declaration=True)
    manifest = {'bundle_id': identifier, 'feed': feed_url, 'server': str(server), **apps}
    (args.output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__': main()
