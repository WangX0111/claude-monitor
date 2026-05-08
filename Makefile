PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin

.PHONY: check test install uninstall

check:
	bash -n claude-monitor.sh
	bash -n tests/smoke.sh

test: check
	bash tests/smoke.sh

install:
	install -d "$(BINDIR)"
	install -m 0755 claude-monitor.sh "$(BINDIR)/claude-monitor"

uninstall:
	rm -f "$(BINDIR)/claude-monitor"
