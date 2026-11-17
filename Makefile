# PANOPTES_SERVER=/path/to/panoptes-server (built from github.com/DonSosiska/panoptes)
PANOPTES_SERVER ?=
SEQ ?= 1
DIST ?= dist

.PHONY: validate bundle check-server

check-server:
	@test -n "$(PANOPTES_SERVER)" -a -x "$(PANOPTES_SERVER)" || { echo "set PANOPTES_SERVER=/path/to/panoptes-server"; exit 1; }

# Validates the rules, runs their tests and checks the coverage policy; the bundle goes to a temp dir.
validate: check-server
	@out="$$(mktemp -d)"; trap 'rm -rf -- "$$out"' EXIT; \
	"$(PANOPTES_SERVER)" rules build -rules rules -tests tests -seq 1 -out "$$out"

# Unsigned bundle in $(DIST) (SEQ=N). Sign with: panoptes-server rules sign -key <file> $(DIST)/rules-N.tar.gz
bundle: check-server
	"$(PANOPTES_SERVER)" rules build -rules rules -tests tests -seq $(SEQ) -out $(DIST)
