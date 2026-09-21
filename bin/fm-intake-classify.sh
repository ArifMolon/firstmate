#!/usr/bin/env bash
# fm-intake-classify.sh - advisory intake classification of the captain's own
# words with typesafe.ai's System One model (Jev): the deliverable kind, the
# product surface, and teammate-area overlap, answered in one request.
#
# Usage:
#   fm-intake-classify.sh [--message <text>]... [--context <text>] [--area <name>]... [--model <id>] [--json] [<request text>]
#   fm-intake-classify.sh < request.txt
#
#   --message <text>  one earlier captain message; repeat in order, oldest first.
#   <request text>    the current instruction, appended last; with no positional
#                     and no --message the current instruction is read from stdin.
#   --context <text>  background the assistant already knows (default empty).
#   --area <name>     one code area a teammate is working on; repeat per area.
#   --model <id>      override the pinned model for this one call.
#   --json            print the raw response with the verdicts added under
#                     `verdicts` instead of the line output below.
#
# Questions, model pin, and thresholds come from bin/fm-intake-questions.json
# beside this script: the three question entries are sent verbatim, `model`
# pins the version the thresholds were measured on, `thresholds.act` is the
# confidence at or above which a Choice answer is `act`, and
# `thresholds.overlap` is the Noul probability at or above which teammate
# overlap is `yes`. State sent: {"messages": [...oldest first...],
# "context": "<text or empty>", "teammate_areas": [...]}.
#
# Key: TYPESAFE_API_KEY non-empty in this process environment, else a
#   TYPESAFE_API_KEY= line in $FM_HOME/.env read with fmx_env_get, the same
#   accessor as FMX_PAIRING_TOKEN and bin/fm-dispatch-resolve.sh
#   (bin/fm-env-lib.sh). The environment wins. The key lives in one private
#   non-exported variable, is unset before any child process, and reaches curl
#   only as a header read from a file descriptor, never on argv; nothing
#   prints, logs, or writes it.
#
# Request: one POST to https://api.typesafe.ai/v1/systemone (fixed, like the
#   resolver), 20 s timeout, one retry on HTTP 429 or 529 after the response's
#   Retry-After seconds capped at 10 (1 s when absent or not a whole number).
#
# Output (stdout), one line each:
#   model=<id>
#   input_tokens=<n>
#   kind=<choice> confidence=<0..1> verdict=<act|ask>
#   surface=<choice> confidence=<0..1> verdict=<act|ask>
#   teammate_overlap=<0..1> verdict=<yes|no>[ near-threshold]
#   `verdict=act` only when confidence is at or above thresholds.act;
#   `verdict=yes` when the Noul is at or above thresholds.overlap; the
#   near-threshold marker appears when the Noul is within 0.15 of that.
#
# Exit codes:
#   0  answered
#   2  usage error (no request text, unknown flag, unreadable questions file,
#      missing jq or curl)
#   3  `not measured: TYPESAFE_API_KEY is not set` on stderr, no request made
#   4  request failure: the HTTP status and body on stderr, naming 401 (missing
#      or invalid key), 422 (body failed validation), 429 (rate limit), and
#      529 (overloaded) as the API quick reference does; also a transport
#      failure or a response that is not the expected answer set
#   The tool never guesses an answer, never writes under state/ or data/, and
#   only advises: AGENTS.md section 7 owns what firstmate does with a verdict,
#   docs/configuration.md "Intake classification" owns the operator contract.
set -u

TYPESAFE_API_KEY_PRIVATE=${TYPESAFE_API_KEY:-}
export -n TYPESAFE_API_KEY_PRIVATE 2>/dev/null || true
unset TYPESAFE_API_KEY

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-$FM_ROOT}"
QUESTIONS="$SCRIPT_DIR/fm-intake-questions.json"

# shellcheck source=bin/fm-env-lib.sh
. "$SCRIPT_DIR/fm-env-lib.sh"

TS_BASE=https://api.typesafe.ai
TS_TIMEOUT=20
RETRY_AFTER_MAX=10
NEAR_THRESHOLD=0.15

die() { printf 'fm-intake-classify: %s\n' "$1" >&2; exit 2; }
usage() {
  awk '
    NR == 1 { next }
    /^#/ { sub(/^# ?/, ""); print; next }
    { exit }
  ' "$0"
}

MESSAGES='[]' AREAS='[]' CONTEXT='' MODEL='' JSON=0 REQUEST_TEXT='' HAVE_REQUEST=0
command -v jq >/dev/null 2>&1 || die "jq required"
add_message() { MESSAGES=$(jq -c --arg m "$1" '. + [$m]' <<<"$MESSAGES"); }
while [ $# -gt 0 ]; do
  case "$1" in
    --message) [ $# -ge 2 ] || die "--message needs a value"; add_message "$2"; shift 2 ;;
    --context) [ $# -ge 2 ] || die "--context needs a value"; CONTEXT=$2; shift 2 ;;
    --area) [ $# -ge 2 ] || die "--area needs a value"; AREAS=$(jq -c --arg a "$2" '. + [$a]' <<<"$AREAS"); shift 2 ;;
    --model) [ $# -ge 2 ] || die "--model needs a value"; MODEL=$2; shift 2 ;;
    --json) JSON=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; [ $# -le 1 ] || die "one request text only"; [ $# -eq 0 ] || { REQUEST_TEXT=$1; HAVE_REQUEST=1; }; break ;;
    -*) die "unknown flag $1 (see --help)" ;;
    *) [ "$HAVE_REQUEST" -eq 0 ] || die "one request text only"; REQUEST_TEXT=$1; HAVE_REQUEST=1; shift ;;
  esac
done
if [ "$HAVE_REQUEST" -eq 0 ] && [ "$MESSAGES" = '[]' ]; then
  REQUEST_TEXT=$(cat) || die "could not read the request from stdin"
  HAVE_REQUEST=1
fi
[ "$HAVE_REQUEST" -eq 0 ] || add_message "$REQUEST_TEXT"
[ "$(jq -r 'map(select(length > 0)) | length' <<<"$MESSAGES")" -gt 0 ] || die "request text required (positional, --message, or stdin; see --help)"

[ -r "$QUESTIONS" ] || die "questions file not readable: $QUESTIONS"
jq -e '
  (.model | type) == "string" and (.model | length) > 0 and
  (.thresholds.act | type) == "number" and (.thresholds.overlap | type) == "number" and
  (.questions | type) == "object" and (.questions | keys | sort) == ["kind", "surface", "teammate_overlap"] and
  .questions.kind.type == "choice" and .questions.surface.type == "choice" and .questions.teammate_overlap.type == "noul"
' "$QUESTIONS" >/dev/null 2>&1 || die "questions file is malformed: $QUESTIONS"
[ -n "$MODEL" ] || MODEL=$(jq -r '.model' "$QUESTIONS")
ACT=$(jq -r '.thresholds.act' "$QUESTIONS")
OVERLAP=$(jq -r '.thresholds.overlap' "$QUESTIONS")

# ---- key ---------------------------------------------------------------------
if [ -z "$TYPESAFE_API_KEY_PRIVATE" ]; then
  TYPESAFE_API_KEY_PRIVATE=$(fmx_env_get TYPESAFE_API_KEY "$FM_HOME/.env")
fi
if [ -z "$TYPESAFE_API_KEY_PRIVATE" ]; then
  echo "not measured: TYPESAFE_API_KEY is not set" >&2
  exit 3
fi
command -v curl >/dev/null 2>&1 || die "curl required"

# ---- request -----------------------------------------------------------------
REQUEST=$(jq -n --slurpfile q "$QUESTIONS" --argjson messages "$MESSAGES" --arg context "$CONTEXT" \
  --argjson areas "$AREAS" --arg model "$MODEL" '
  {model: $model, state: {messages: $messages, context: $context, teammate_areas: $areas}, questions: $q[0].questions}') \
  || die "could not build the request"

RESP_FILE=$(mktemp) || die "mktemp failed"
HDR_FILE=$(mktemp) || { rm -f "$RESP_FILE"; die "mktemp failed"; }
ERR_FILE=$(mktemp) || { rm -f "$RESP_FILE" "$HDR_FILE"; die "mktemp failed"; }
trap 'rm -f "$RESP_FILE" "$HDR_FILE" "$ERR_FILE"' EXIT

post() {
  : > "$RESP_FILE"; : > "$HDR_FILE"; : > "$ERR_FILE"
  HTTP=$(printf '%s' "$REQUEST" | curl -sS --max-time "$TS_TIMEOUT" -o "$RESP_FILE" -D "$HDR_FILE" -w '%{http_code}' \
    -X POST "$TS_BASE/v1/systemone" -H 'Content-Type: application/json' \
    -H @/dev/fd/3 3< <(printf 'Authorization: Bearer %s\n' "$TYPESAFE_API_KEY_PRIVATE") \
    --data-binary @- 2>"$ERR_FILE") || HTTP=000
}

retry_after_secs() {
  local value
  value=$(grep -i '^retry-after:' "$HDR_FILE" 2>/dev/null | tail -n1 | cut -d: -f2- | tr -d ' \t\r')
  case "$value" in
    ''|*[!0-9]*) value=1 ;;
  esac
  [ "$value" -le "$RETRY_AFTER_MAX" ] || value=$RETRY_AFTER_MAX
  printf '%s\n' "$value"
}

post
case "$HTTP" in
  429|529)
    sleep "$(retry_after_secs)"
    post
    ;;
esac

request_failed() {
  local status=$1 detail=$2 body
  body=$(head -c 400 "$RESP_FILE" 2>/dev/null | tr '\n' ' ')
  printf 'fm-intake-classify: request failed: HTTP %s%s: %s\n' "$status" "$detail" "$body" >&2
  exit 4
}

case "$HTTP" in
  200) ;;
  000) request_failed 000 " (no response: $(head -c 200 "$ERR_FILE" 2>/dev/null | tr '\n' ' '))" ;;
  401) request_failed 401 " (missing or invalid key: fix TYPESAFE_API_KEY, do not retry)" ;;
  422) request_failed 422 " (body failed validation; the body names the field)" ;;
  429) request_failed 429 " (rate limit; retried once honoring Retry-After)" ;;
  529) request_failed 529 " (overloaded; retried once)" ;;
  *) request_failed "$HTTP" "" ;;
esac

jq -e '
  (.model | type) == "string" and
  (.answers.kind.choice | type) == "string" and (.answers.kind.confidence | type) == "number" and
  (.answers.surface.choice | type) == "string" and (.answers.surface.confidence | type) == "number" and
  (.answers.teammate_overlap.noul | type) == "number"
' "$RESP_FILE" >/dev/null 2>&1 || request_failed 200 " (response is not the expected kind, surface, and teammate_overlap answer set)"

# ---- verdicts ----------------------------------------------------------------
RESULT=$(jq --argjson act "$ACT" --argjson overlap "$OVERLAP" --argjson near "$NEAR_THRESHOLD" '
  def verdict($c): if $c >= $act then "act" else "ask" end;
  (.answers.teammate_overlap.noul) as $n |
  . + {verdicts: {
    kind: verdict(.answers.kind.confidence),
    surface: verdict(.answers.surface.confidence),
    teammate_overlap: (if $n >= $overlap then "yes" else "no" end),
    near_threshold: (((($n - $overlap) | fabs) * 1000 | round) <= ($near * 1000 | round)),
    thresholds: {act: $act, overlap: $overlap}
  }}' "$RESP_FILE") || request_failed 200 " (could not compute verdicts)"

if [ "$JSON" -eq 1 ]; then
  printf '%s\n' "$RESULT"
  exit 0
fi

jq -r '
  def flat: tostring | gsub("[\t\r\n]"; " ");
  "model=\(.model | flat)",
  "input_tokens=\((.usage.input_tokens // "unknown") | flat)",
  "kind=\(.answers.kind.choice | flat) confidence=\(.answers.kind.confidence | flat) verdict=\(.verdicts.kind)",
  "surface=\(.answers.surface.choice | flat) confidence=\(.answers.surface.confidence | flat) verdict=\(.verdicts.surface)",
  ("teammate_overlap=\(.answers.teammate_overlap.noul | flat) verdict=\(.verdicts.teammate_overlap)" + (if .verdicts.near_threshold then " near-threshold" else "" end))
' <<<"$RESULT"
exit 0
