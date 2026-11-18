# HOLEALIGN_SERVER=/path/to/holealign-server (built from github.com/DonSosiska/holealign)
HOLEALIGN_SERVER ?=
SEQ ?= 1
DIST ?= dist

.PHONY: validate bundle check-server

check-server:
	@test -n "$(HOLEALIGN_SERVER)" -a -x "$(HOLEALIGN_SERVER)" || { echo "set HOLEALIGN_SERVER=/path/to/holealign-server"; exit 1; }

# Validates the rules, runs their tests and checks the coverage policy; the bundle goes to a temp dir.
validate: check-server
	@out="$$(mktemp -d)"; trap 'rm -rf -- "$$out"' EXIT; \
	"$(HOLEALIGN_SERVER)" rules build -rules rules -tests tests -seq 1 -out "$$out"

# Unsigned bundle in $(DIST) (SEQ=N). Sign with: holealign-server rules sign -key <file> $(DIST)/rules-N.tar.gz
bundle: check-server
	"$(HOLEALIGN_SERVER)" rules build -rules rules -tests tests -seq $(SEQ) -out $(DIST)
