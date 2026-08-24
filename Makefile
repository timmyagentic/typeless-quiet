.PHONY: test build assets app dmg verify

test:
	swift test

build:
	swift build --configuration release --product TypelessQuiet

assets:
	swift scripts/generate-assets.swift Resources

app:
	./scripts/build-app.sh

dmg: app
	./scripts/make-dmg.sh "dist/Typeless Quiet.app" "dist/Typeless-Quiet-local.dmg"

verify:
	./scripts/verify.sh
