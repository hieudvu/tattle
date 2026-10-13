.PHONY: d p test clean

# Dev build: "Tattle Dev.app" (bundle id ...tattle.dev). Rebuilds and relaunches.
# Avoid looping on this: each launch re-registers the app with macOS.
d:
	@pkill -x "Tattle Dev" || true
	scripts/bundle.sh dev
	open "build/Tattle Dev.app"

# Production build: "Tattle.app", no dev suffix anywhere. Does not launch.
p:
	scripts/bundle.sh production

# Tests only ever link TattleCore (all mocks); they never touch the host.
test:
	swift test

clean:
	rm -rf build .build
