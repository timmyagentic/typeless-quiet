.PHONY: test build assets app dmg verify

test:
	swift test

build:
	swift build --configuration release --product TypelessPlusPlus

assets:
	swift scripts/generate-assets.swift Resources

app:
	./scripts/build-app.sh

dmg: app
	./scripts/make-dmg.sh "dist/Typeless++.app" "dist/TypelessPlusPlus-local.dmg"

verify:
	./scripts/verify.sh
