import base64
import importlib.util
import pathlib
import unittest
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location('update_feed', pathlib.Path(__file__).parents[1] / 'update-feed.py')
feed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(feed)


class UpdateFeedTests(unittest.TestCase):
    def metadata(self, build='10', channel='beta'):
        return {'CFBundleIdentifier': feed.BUNDLE_ID, 'CFBundleVersion': build,
                'CFBundleShortVersionString': '0.0.1', 'TypelessUpdateChannel': channel,
                'SUPublicEDKey': base64.b64encode(b'k' * 32).decode(), 'LSMinimumSystemVersion': '13.0'}

    def item(self, build='10', channel='beta'):
        return feed.make_item(self.metadata(build, channel),
                              'v0.0.1-beta.4' if channel == 'beta' else 'v0.0.1',
                              'TypelessPlusPlus.zip', base64.b64encode(b's' * 64).decode(), 42)

    def test_stable_is_channel_less_and_beta_is_explicit(self):
        self.assertIsNone(self.item(channel='stable').find(feed.S + 'channel'))
        self.assertEqual(self.item().findtext(feed.S + 'channel'), 'beta')
        self.assertEqual(self.item().findtext(feed.S + 'version'), '10')

    def test_metadata_rejects_wrong_app_key_channel_and_non_numeric_build(self):
        for key, value in [('CFBundleIdentifier', 'wrong'), ('CFBundleVersion', '0.0.1'),
                           ('SUPublicEDKey', 'bad'), ('TypelessUpdateChannel', 'private-beta')]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                feed.validate_metadata({**self.metadata(), key: value})

    def test_tag_and_bundled_channel_must_agree(self):
        with self.assertRaises(ValueError):
            feed.make_item(self.metadata(), 'v0.0.1', 'app.zip', 'x', 42)
        with self.assertRaises(ValueError):
            feed.make_item(self.metadata(channel='stable'), 'v0.0.1-beta.4', 'app.zip', 'x', 42)
        with self.assertRaises(ValueError):
            feed.make_item(self.metadata(), 'v0.0.2-beta.4', 'app.zip', 'x', 42)

    def test_next_build_must_exceed_every_feed_item_not_just_first(self):
        tree = feed.empty_feed()
        channel = tree.getroot().find('channel')
        channel.append(self.item('10'))
        channel.append(self.item('20', 'stable'))
        with self.assertRaises(ValueError):
            feed.append_item(tree, self.item('11'))
        feed.append_item(tree, self.item('21'))
        self.assertEqual(channel.find('item').findtext(feed.S + 'version'), '21')
        self.assertEqual(len(channel.findall('item')), 3)

    def test_feed_rejects_unsigned_http_foreign_urls_duplicate_builds(self):
        for kind in ['signature', 'url', 'foreign', 'duplicate']:
            with self.subTest(kind=kind):
                tree = feed.empty_feed()
                item = self.item()
                tree.getroot().find('channel').append(item)
                enc = item.find('enclosure')
                if kind == 'signature': enc.attrib.pop(feed.S + 'edSignature')
                if kind == 'url': enc.set('url', enc.get('url').replace('https:', 'http:'))
                if kind == 'foreign': enc.set('url', 'https://example.com/app.zip')
                if kind == 'duplicate': tree.getroot().find('channel').append(self.item())
                with self.assertRaises(ValueError): feed.validate_feed(tree)

    def test_feed_display_version_matches_download_tag(self):
        tree = feed.empty_feed()
        item = self.item()
        item.find(feed.S + 'shortVersionString').text = '9.9.9'
        tree.getroot().find('channel').append(item)
        with self.assertRaises(ValueError): feed.validate_feed(tree)

    def test_empty_bootstrap_feed_is_valid(self):
        feed.validate_feed(feed.empty_feed())

    def test_archive_filename_cannot_escape_release_url(self):
        for filename in ['../app.zip', 'app.zip?token=x', 'app.zip#fragment']:
            with self.assertRaises(ValueError):
                feed.make_item(self.metadata(), 'v0.0.1-beta.4', filename, 'x', 42)


if __name__ == '__main__': unittest.main()
