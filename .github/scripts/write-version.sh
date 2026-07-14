#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?usage: write-version.sh <version>}"

cat > lib/has_state_machine/version.rb <<EOF
# frozen_string_literal: true

module HasStateMachine
  VERSION = "${VERSION}"
end
EOF
