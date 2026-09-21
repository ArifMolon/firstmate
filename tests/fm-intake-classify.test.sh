#!/usr/bin/env bash
# Behavior tests for bin/fm-intake-classify.sh.
#
# Drives the public argv, stdin, and environment interface with a fake curl on
# PATH, the same shape tests/fm-dispatch-resolve.test.sh uses: it records
# argv, the request body it read from stdin, the header it read from file
# descriptor 3, and whether the secret reached its environment, then answers
# with a canned typesafe.ai response. No case touches the network, and the
# absent-key case proves the tool makes no call at all.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# The operator's shell may carry the real key; every case below sets the key
# it means to test, so the ambient one must never leak into a case.
unset TYPESAFE_API_KEY

TOOL="$ROOT/bin/fm-intake-classify.sh"
QUESTIONS="$ROOT/bin/fm-intake-questions.json"
TMP_ROOT=$(fm_test_tmproot fm-intake-classify)
HOME_DIR="$TMP_ROOT/home"
FAKEBIN=$(fm_fakebin "$TMP_ROOT")
LOG="$TMP_ROOT/log"
RESPONSE="$TMP_ROOT/response.json"
ERROR_BODY="$TMP_ROOT/error-body.json"
BASE_PATH=$PATH
mkdir -p "$HOME_DIR" "$LOG"

cat > "$FAKEBIN/curl" <<'SH'
#!/usr/bin/env bash
# Fake curl: records argv (minus the -o target), the stdin body, the header
# read from fd 3, and one line per call; answers with FAKE_CURL_HTTP (default
# 200), copying FAKE_CURL_RESPONSE for a 200 and FAKE_CURL_ERROR_BODY
# otherwise.
set -u
if [ -n "${TYPESAFE_API_KEY+x}" ] || [ -n "${TYPESAFE_API_KEY_PRIVATE+x}" ]; then
  printf 'curl:secret-present\n' >> "${CHILD_ENV_LOG:?}"
else
  printf 'curl:clean\n' >> "${CHILD_ENV_LOG:?}"
fi
out=''
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out=$2; shift 2 ;;
    *) printf '%s\n' "$1" >> "${FAKE_CURL_LOG:?}/argv"; shift ;;
  esac
done
cat > "$FAKE_CURL_LOG/body"
cat /dev/fd/3 > "$FAKE_CURL_LOG/header" 2>/dev/null || printf 'fd3 unreadable\n' > "$FAKE_CURL_LOG/header"
printf 'call\n' >> "$FAKE_CURL_LOG/calls"
if [ "${FAKE_CURL_FAIL:-0}" = 1 ]; then
  echo 'curl: (7) Failed to connect' >&2
  exit 7
fi
code=${FAKE_CURL_HTTP:-200}
if [ "$code" = 200 ]; then
  cp "${FAKE_CURL_RESPONSE:?}" "$out"
else
  cp "${FAKE_CURL_ERROR_BODY:?}" "$out"
fi
printf '%s' "$code"
SH
chmod +x "$FAKEBIN/curl"

export FAKE_CURL_LOG="$LOG" FAKE_CURL_RESPONSE="$RESPONSE" FAKE_CURL_ERROR_BODY="$ERROR_BODY" CHILD_ENV_LOG="$LOG/child-env"

write_response() {  # <path> <kind> <kind-confidence> <surface> <surface-confidence> <noul>
  cat > "$1" <<JSON
{ "model": "jev-1.13.0",
  "answers": {
    "kind": { "type": "choice", "choice": "$2", "confidence": $3,
      "probabilities": { "ship": 0.9, "scout": 0.05, "decision": 0.02, "answer_or_instruction": 0.02, "other": 0.01 } },
    "surface": { "type": "choice", "choice": "$4", "confidence": $5,
      "probabilities": { "internal_tooling": 0.8, "product_facing": 0.1, "mixed_or_unclear": 0.1 } },
    "teammate_overlap": { "type": "noul", "noul": $6 }
  },
  "usage": { "input_tokens": 1012, "output_tokens": 40 } }
JSON
}

reset_log() {
  rm -rf "$LOG"
  mkdir -p "$LOG"
}

# run <exit-var> <out-var> <err-var> [args...]: the tool with fakebin first on
# PATH and an isolated FM_HOME; TYPESAFE_API_KEY comes from the caller's env.
run() {
  local __exit=$1 __out=$2 __err=$3 _out _code
  shift 3
  _out=$(PATH="$FAKEBIN:$BASE_PATH" FM_HOME="$HOME_DIR" "$TOOL" "$@" 2> "$TMP_ROOT/stderr")
  _code=$?
  printf -v "$__exit" '%s' "$_code"
  printf -v "$__out" '%s' "$_out"
  printf -v "$__err" '%s' "$(cat "$TMP_ROOT/stderr")"
}

KEY='test-key-4b7e9a1c-never-on-argv'
code='' out='' err=''
printf '%s\n' '{"error":"canned failure body FAKE-ERR-BODY"}' > "$ERROR_BODY"
write_response "$RESPONSE" ship 0.91 internal_tooling 0.83 0.12

# --- absent key: exit 3, explicit stderr line, no request -----------------------
reset_log
run code out err "login sayfasındaki hatayı düzelt"
expect_code 3 "$code" "absent key exits 3"
assert_equals '' "$out" "absent key prints nothing on stdout"
assert_equals 'not measured: TYPESAFE_API_KEY is not set' "$err" "absent key names itself on stderr"
assert_absent "$LOG/argv" "absent key never calls curl"
pass "absent key is reported explicitly with no request"

# --- usage errors exit 2 before any request -----------------------------------
reset_log
TYPESAFE_API_KEY=$KEY run code out err --bogus
expect_code 2 "$code" "unknown flag exits 2"
TYPESAFE_API_KEY=$KEY run code out err --model jev-preview 'hatayı düzelt'
expect_code 2 "$code" "--model is not a flag"
TYPESAFE_API_KEY=$KEY run code out err --json 'hatayı düzelt'
expect_code 2 "$code" "--json is not a flag"
TYPESAFE_API_KEY=$KEY run code out err < /dev/null
expect_code 2 "$code" "empty stdin exits 2"
assert_contains "$err" 'request text required' "empty request names the missing input"
TYPESAFE_API_KEY=$KEY run code out err --message
expect_code 2 "$code" "a flag without its value exits 2"
assert_absent "$LOG/argv" "usage errors never call curl"
pass "usage errors exit 2 without a request"

# --- .env key, and the environment wins over it ---------------------------------
printf '%s\n' '# local secrets' 'FMX_PAIRING_TOKEN=abc' "export TYPESAFE_API_KEY=\"$KEY\"" > "$HOME_DIR/.env"
reset_log
run code out err "login sayfasındaki hatayı düzelt"
expect_code 0 "$code" ".env key answers"
assert_equals "Authorization: Bearer $KEY" "$(cat "$LOG/header")" ".env key reaches curl on the fd header"
reset_log
TYPESAFE_API_KEY=env-wins run code out err "login sayfasındaki hatayı düzelt"
assert_equals 'Authorization: Bearer env-wins' "$(cat "$LOG/header")" "environment key wins over .env"
rm -f "$HOME_DIR/.env"
pass "TYPESAFE_API_KEY= in .env activates the tool and the environment wins"

# --- request shape, secret handling, default output -----------------------------
reset_log
TYPESAFE_API_KEY=$KEY run code out err --message 'ilk mesaj' --message 'ikinci mesaj' \
  --context 'carbonorm admin console' --area Suppliers --area Packaging 'son mesaj: hatayı düzelt'
expect_code 0 "$code" "answered exits 0"
body=$(cat "$LOG/body")
assert_equals '["ilk mesaj","ikinci mesaj","son mesaj: hatayı düzelt"]' "$(jq -c .state.messages <<<"$body")" "messages ride oldest first with the request last"
assert_equals 'carbonorm admin console' "$(jq -r .state.context <<<"$body")" "context rides in the state"
assert_equals '["Suppliers","Packaging"]' "$(jq -c .state.teammate_areas <<<"$body")" "areas ride in order"
assert_equals '["kind","surface","teammate_overlap"]' "$(jq -c '.questions | keys' <<<"$body")" "the three question ids are asked"
assert_equals 'jev-1.13.0' "$(jq -r .model <<<"$body")" "the pinned model is sent"
assert_equals "$(jq -c .questions "$QUESTIONS")" "$(jq -c .questions <<<"$body")" "the questions are sent verbatim from the questions file"
argv=$(cat "$LOG/argv")
assert_not_contains "$argv" "$KEY" "the key never appears on curl argv"
assert_contains "$argv" 'https://api.typesafe.ai/v1/systemone' "the request uses the fixed typesafe.ai endpoint"
assert_contains "$argv" $'--max-time\n20' "the request uses the twenty-second timeout"
assert_contains "$argv" '@/dev/fd/3' "the header is read from a file descriptor"
assert_equals "Authorization: Bearer $KEY" "$(cat "$LOG/header")" "curl receives the bearer header on fd 3"
assert_equals 'curl:clean' "$(cat "$LOG/child-env")" "the API key is absent from the child environment"
assert_equals '1' "$(wc -l < "$LOG/calls" | tr -d ' ')" "a 200 answer makes exactly one call"
assert_not_contains "$out$err" "$KEY" "the key never appears on stdout or stderr"
assert_equals $'model=jev-1.13.0\ninput_tokens=1012\nkind=ship confidence=0.91 verdict=act\nsurface=internal_tooling confidence=0.83 verdict=act\nteammate_overlap=0.12 verdict=no' "$out" "default output is one line per fact"
pass "request shape, fixed endpoint, fd-only key, and line output"

# --- stdin request, empty context and areas -------------------------------------
reset_log
TYPESAFE_API_KEY=$KEY run code out err <<<'stdin üzerinden gelen istek'
expect_code 0 "$code" "stdin request exits 0"
body=$(cat "$LOG/body")
assert_equals '["stdin üzerinden gelen istek"]' "$(jq -c .state.messages <<<"$body")" "stdin becomes the single message"
assert_equals '""' "$(jq -c .state.context <<<"$body")" "context defaults to empty"
assert_equals '[]' "$(jq -c .state.teammate_areas <<<"$body")" "areas default to empty"
pass "stdin carries the request when no positional or --message is given"

# --- verdict mapping around the act and overlap thresholds ----------------------
verdict_case() {  # <kind-conf> <surface-conf> <noul> <expected kind line> <expected surface line> <expected overlap line>
  reset_log
  write_response "$RESPONSE" scout "$1" product_facing "$2" "$3"
  TYPESAFE_API_KEY=$KEY run code out err 'rapor yaz'
  expect_code 0 "$code" "verdict case $1/$2/$3 exits 0"
  assert_contains "$out" "$4" "kind verdict at confidence $1"
  assert_contains "$out" "$5" "surface verdict at confidence $2"
  assert_contains "$out" "$6" "overlap verdict at noul $3"
}
verdict_case 0.7 0.69 0.7 'kind=scout confidence=0.7 verdict=act' 'surface=product_facing confidence=0.69 verdict=ask' 'teammate_overlap=0.7 verdict=yes'
verdict_case 0.71 0.7 0.69 'kind=scout confidence=0.71 verdict=act' 'surface=product_facing confidence=0.7 verdict=act' 'teammate_overlap=0.69 verdict=no'
verdict_case 0.69 0.99 0.87 'kind=scout confidence=0.69 verdict=ask' 'surface=product_facing confidence=0.99 verdict=act' 'teammate_overlap=0.87 verdict=yes'
verdict_case 0.2 0.2 0.56 'kind=scout confidence=0.2 verdict=ask' 'surface=product_facing confidence=0.2 verdict=ask' 'teammate_overlap=0.56 verdict=no'
verdict_case 1 1 0.04 'kind=scout confidence=1 verdict=act' 'surface=product_facing confidence=1 verdict=act' 'teammate_overlap=0.04 verdict=no'
pass "verdicts map at, above, and below the act and overlap thresholds"

# --- 401, 422, 429, 529: exit 4, status and body on stderr, one call, no output --
for status in 401 422 429 529; do
  reset_log
  FAKE_CURL_HTTP=$status TYPESAFE_API_KEY=$KEY run code out err 'hatayı düzelt'
  expect_code 4 "$code" "HTTP $status exits 4"
  assert_equals '' "$out" "HTTP $status prints nothing on stdout"
  assert_contains "$err" "request failed: HTTP $status" "HTTP $status is named"
  assert_contains "$err" 'FAKE-ERR-BODY' "HTTP $status surfaces the body"
  assert_equals '1' "$(wc -l < "$LOG/calls" | tr -d ' ')" "HTTP $status is not retried"
  assert_not_contains "$err" "$KEY" "HTTP $status never prints the key"
done
FAKE_CURL_HTTP=401 TYPESAFE_API_KEY=$KEY run code out err 'hatayı düzelt'
assert_contains "$err" 'missing or invalid key' "401 is explained as the quick reference does"
FAKE_CURL_HTTP=422 TYPESAFE_API_KEY=$KEY run code out err 'hatayı düzelt'
assert_contains "$err" 'body failed validation' "422 is explained as the quick reference does"
FAKE_CURL_HTTP=429 TYPESAFE_API_KEY=$KEY run code out err 'hatayı düzelt'
assert_contains "$err" 'rate limit' "429 is explained as the quick reference does"
FAKE_CURL_HTTP=529 TYPESAFE_API_KEY=$KEY run code out err 'hatayı düzelt'
assert_contains "$err" 'overloaded' "529 is explained as the quick reference does"
pass "401, 422, 429, and 529 exit 4 with the status and body on stderr and no retry"

# --- transport failure and malformed response ----------------------------------
reset_log
FAKE_CURL_FAIL=1 TYPESAFE_API_KEY=$KEY run code out err 'hatayı düzelt'
expect_code 4 "$code" "transport failure exits 4"
assert_contains "$err" 'request failed: HTTP 000 (no response: curl: (7) Failed to connect' "transport failure names curl's error"

reset_log
printf '%s\n' '{"model":"jev-1.13.0","answers":{"kind":{"type":"choice","choice":"ship","confidence":0.9}}}' > "$RESPONSE"
TYPESAFE_API_KEY=$KEY run code out err 'hatayı düzelt'
expect_code 4 "$code" "a partial answer set exits 4"
assert_contains "$err" 'not the expected kind, surface, and teammate_overlap answer set' "a partial answer set is named"
assert_equals '' "$out" "a partial answer set prints no guessed answer"
pass "transport failures and malformed responses never yield a guessed answer"

# --- nothing is written under state/ or data/ ----------------------------------
assert_absent "$HOME_DIR/state" "the tool writes nothing under state/"
assert_absent "$HOME_DIR/data" "the tool writes nothing under data/"
pass "the tool keeps the home untouched"

echo "# all fm-intake-classify tests passed"
