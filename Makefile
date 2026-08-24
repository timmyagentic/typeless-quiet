.PHONY: test build app verify

test:
	swift test

build:
	swift build --configuration release --product TypelessQuiet

app:
	./scripts/build-app.sh

verify:
	./scripts/verify.sh
