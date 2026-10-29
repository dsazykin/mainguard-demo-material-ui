#!/usr/bin/env bash
# W7b/W7c, mui/material-ui: the repository's own CI tests, reported per test as TAP on standard output (every other output goes to
# standard error). Its CI (CircleCI) runs, besides lint, `tsc`, the build and docs checks that stay out:
#   test_unit         `yarn test:coverage`: the mocha unit tests (here `test:unit`, the same files without coverage)
#   test_browser      `yarn test:karma`: the same sources in a real browser (Chrome headless; PhantomJS at the 2018 bases)
#   test_e2e          `yarn test:e2e`: the end-to-end mocha tests in Chrome (2023 bases)
# Not run, because they need the internet, which a jail does not have (NOTES.md): `test:regressions` (Google Fonts and Font Awesome
# are fetched, and the test waits for them; at the 2018 base it needs a Selenium service container and Argos), the UMD bundle test
# (it loads React and Babel from a CDN), the bundling fixtures (`yarn install`), and the Firefox and BrowserStack karma browsers.
#
#   suite.sh                  the whole suite (what `.mainguard/verify` runs)
#   suite.sh FILE...          only those test files (what `.mainguard/sealed` runs, with {files}): the mocha unit tests
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 70

if command -v mg-link-deps >/dev/null 2>&1; then
  mg-link-deps --check "$PWD" >&2; rc=$?
  # 3: a copied path (or a directory the tree has itself) was left alone, which is fine
  { [ "$rc" -eq 0 ] || [ "$rc" -eq 3 ]; } || exit 70
fi

export NVM_DIR="${NVM_DIR:-/usr/local/nvm}"
# shellcheck disable=SC1091
if [ -s "$NVM_DIR/nvm.sh" ]; then . "$NVM_DIR/nvm.sh" >/dev/null 2>&1; nvm use default >/dev/null 2>&1; fi
# BROWSERSLIST_IGNORE_OLD_DATA: browserslist warns once caniuse-lite is older than a few months, and mui's tests fail a test that
# warns, so a base that was green when the image was made would turn red by the calendar alone.
# CI and CIRCLECI as the repository's CI sets them: its mocha and karma timeouts are longer on CircleCI (5 s instead of 2 s, 6 s in the
# browser), and `CI` changes what its karma and webpack configurations do. Without them a jail that sets CI (the verification jail) and
# one that does not (the agent's) would run different suites.
export NODE_ENV=test FORCE_COLOR=0 BROWSERSLIST_IGNORE_OLD_DATA=1 CI=true CIRCLECI=true

if [ -f pnpm-lock.yaml ]; then pm="pnpm --silent"; else pm="npm --silent"; fi    # the script runner only; npm runs a yarn-installed tree's scripts too

if [ "$#" -gt 0 ]; then
  # Only the named files: the repository's own spec globs are replaced by them (mocha merges config `spec` with arguments, so the
  # config is asked for nothing else).
  # mocha 6 on has `--spec`; before that (the 2018 bases, mocha 5) the files are plain arguments and `--spec` would run nothing.
  if [ "$(node_modules/.bin/mocha --version | cut -d. -f1)" -ge 6 ]; then
    exec node_modules/.bin/mocha --reporter tap --spec "$@"
  fi
  exec node_modules/.bin/mocha --reporter tap "$@"
fi

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$work"' EXIT

# One TAP stream on standard output: every "ok"/"not ok" line of a phase's TAP, with the phase's prefix in front of the name.
emit() {   # emit FILE PREFIX
  [ -s "$1" ] || return 0
  awk -v p="$2" '/^(not ok|ok) [0-9]+ / { match($0, /^(not ok|ok) [0-9]+ /); print substr($0, 1, RLENGTH) p substr($0, RLENGTH + 1) }' "$1"
}

status=0
# PD-79: the task's quarantined tests (PD-78: red identically and stably at the base in all three pin-check places), which the run
# writes to .mainguard/quarantine.txt and `.mainguard/verify` names as MG_QUARANTINE, are skipped: quarantine.js (the adapted image's,
# bench/README.md) marks each one that failed as skipped in a runner's report and prints the exit to keep, forgiven only when the run
# reached its end and they were its only failures. Unset (the pin check, a sealed run), nothing changes.
quarantine() {   # quarantine FORMAT REPORT RC [--prefix P] [--exit count|any] [--root DIR]: prints the exit to keep
  local x
  if [ -n "${MG_QUARANTINE:-}" ] && [ -f "$MG_QUARANTINE" ] && x=$(node /opt/mainguard/bench/quarantine.js "$1" "$2" "$3" "$MG_QUARANTINE" "${@:4}"); then
    echo "$x"
  else
    echo "$3"
  fi
}
note() { echo "== $1 (exit $2)" >&2; [ "$2" -eq 0 ] || status=$2; }

# PD-71 item 2: unit tests the benchmark's own image cannot run, left out of a whole run by exact full name (NOTES.md, "Left out by
# name", with each reason). Each fails identically in all three places and passes where the repository's CI ran it.
excluded_tests='listChangedFiles should detect changes
useAutocomplete should warn if the input is not binded
<BottomNavigationAction /> touch functionality should fire onClick on touch tap
<DesktopDateTimePicker /> does not close on click inside
unknown plugin annotates missing error codes
<Tabs /> prop: value warnings hidden tab "before all" hook: test for "should warn if a Tab has display: none"
<Tabs /> prop: value warnings hidden tab "after all" hook for "should warn if a Tab has display: none"'
# drop_excluded FILE RC: FILE without the excluded tests; prints the exit to keep. mocha's exit code is its failure count, so a non-zero
# exit is forgiven only when it is exactly the number of excluded tests that failed and no other test failed.
drop_excluded() {
  local red kept
  red=$(MG_EXCLUDED="$excluded_tests" awk -v out="$1.kept" '
    BEGIN { printf "" > out; n = split(ENVIRON["MG_EXCLUDED"], a, "\n"); for (i = 1; i <= n; i++) if (a[i] != "") x[a[i]] = 1 }
    /^(not ok|ok) [0-9]+ / { t = $0; sub(/^(not ok|ok) [0-9]+ /, "", t); sub(/ # SKIP.*$/, "", t)
                             if (t in x) { if ($0 ~ /^not ok/) red++; next } }
    { print > out }
    END { print red + 0 }' "$1")
  mv "$1.kept" "$1"
  kept=$(grep -c '^not ok ' "$1")
  if [ "$2" -ne 0 ] && [ "$red" -gt 0 ] && [ "$kept" -eq 0 ] && [ "$2" -eq "$red" ]; then
    echo "exit $2 was for the excluded tests only" >&2; echo 0
  else
    echo "$2"
  fi
}

# --- test_unit
$pm run test:unit -- --reporter tap --exit > "$work/unit.tap"   # --exit: older bases leave a handle open and mocha never quits
rc=$(quarantine tap "$work/unit.tap" $? --exit count)           # first: mocha's exit is its failure count, which drop_excluded reads
note unit "$(drop_excluded "$work/unit.tap" "$rc")"
emit "$work/unit.tap" ""

# Karma and the end-to-end tests bundle with webpack. webpack 4 hashes with md4, which node 17 and later (OpenSSL 3) refuse
# (ERR_OSSL_EVP_UNSUPPORTED): on the bases whose image runs webpack 4 on node 18 both suites are red in the benchmark's own image
# before any test runs, so they stay out there (PD-71 item 3), the same in every place.
if ! node -e "require('webpack/lib/util/createHash')('md4').update('x').digest('hex')" >/dev/null 2>&1; then
  echo "webpack $(node -p "require('webpack/package.json').version" 2>/dev/null) cannot hash on node $(node --version) (OpenSSL 3): karma and e2e are red in the benchmark's own image at this base and are left out" >&2
  exit $status
fi

# --- the browser. The benchmark's image keeps the Playwright browsers its CI image had in /root, out of reach of the jail user, whose
# passwordless sudo (the jail's own, adapter prepare-jail.sh) copies Playwright's Chromium to a directory of ours; the unmodified
# image runs as root and uses them where they are. At the 2018 bases the browser is PhantomJS, already in node_modules.
if [ -d node_modules/playwright ] && [ ! -d "$HOME/.cache/ms-playwright" ]; then
  mkdir -p "$work/pw"
  sudo -n sh -c "cp -a /root/.cache/ms-playwright/chromium-* /root/.cache/ms-playwright/ffmpeg-* '$work/pw/' && chown -R $(id -u):$(id -g) '$work/pw'" >&2
  export PLAYWRIGHT_BROWSERS_PATH="$work/pw"
fi
# PhantomJS 2 reads the system's OpenSSL configuration, which on a current distribution names a module it does not have
export OPENSSL_CONF=/dev/null
# The image's `npm install` left ajv-keywords 5 beside ajv 6, so webpack's babel-loader cannot load (`ajv/dist/compile/codegen`), in the
# benchmark's own image as well; the ajv 8 that schema-utils carries is where a failed lookup is retried
[ -d node_modules/schema-utils/node_modules/ajv ] && export NODE_PATH="$PWD/node_modules/schema-utils/node_modules"

# --- test_browser
if [ -f test/karma.conf.js ]; then
  MG_KARMA_TAP="$work/karma.tap" node_modules/.bin/karma start "$here/karma.conf.js" --single-run >&2
  note karma "$(quarantine tap "$work/karma.tap" $? --prefix "[karma] ")"
  emit "$work/karma.tap" "[karma] "
fi

# --- test_e2e (2023 bases): webpack build, the static server the repository's script starts, mocha driving Chromium
if [ -d node_modules/playwright ] && [ -f test/e2e/webpack.config.js ]; then
  ( NODE_ENV=production node_modules/.bin/webpack --config test/e2e/webpack.config.js >&2 ) || note "e2e build" $?
  # the port the tests navigate to (their baseUrl): the repository's `test:e2e:server` is a bare `serve test/e2e`, whose default
  # port moved with serve's version (2021: 5000, 2022: 3000, 2023: 5001)
  port=$(grep -ohE 'localhost:[0-9]+' test/e2e/index.test.* 2>/dev/null | head -1 | cut -d: -f2)
  port=${port:-5001}
  node_modules/.bin/serve test/e2e -p "$port" >&2 &
  srv=$!
  for _ in $(seq 1 60); do (echo > "/dev/tcp/127.0.0.1/$port") 2>/dev/null && break; sleep 1; done
  ( NODE_ENV=production node_modules/.bin/mocha --config test/e2e/.mocharc.js --reporter tap 'test/e2e/**/*.test.{js,ts,tsx}' > "$work/e2e.tap" )
  note e2e "$(quarantine tap "$work/e2e.tap" $? --prefix "[e2e] " --exit count)"
  kill "$srv" 2>/dev/null; wait "$srv" 2>/dev/null
  emit "$work/e2e.tap" "[e2e] "
fi
exit $status
