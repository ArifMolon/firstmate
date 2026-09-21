#!/usr/bin/env bash
# Live guard for bin/fm-intake-classify.sh against the real typesafe.ai API.
#
# Opt-in because every run spends input tokens: set FM_LIVE_TYPESAFE=1 (or
# FM_LIVE=1) to run it. It sends one Turkish request that asks for a fix and
# one that asks for a report and asserts the `kind` verdicts the shipped
# thresholds were measured for; then one request that adds an export button
# to a Suppliers list, once with Suppliers among the teammate areas (surface
# product_facing, overlap yes) and once with no areas (overlap no). It asserts
# a model id is reported and prints that id so
# docs/verification/intake-classify.md can record it. An absent key is a
# failure, never a silent pass: the guard was asked to measure.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fm_live_gate opt-in FM_LIVE_TYPESAFE curl jq

TOOL="$ROOT/bin/fm-intake-classify.sh"
TMP_ROOT=$(fm_test_tmproot fm-intake-classify-live)

classify() {  # <out-var> <label> <request text> [tool flags...]
  local __out=$1 label=$2 request=$3 _out _code
  shift 3
  _out=$("$TOOL" "$@" "$request" 2> "$TMP_ROOT/stderr")
  _code=$?
  case "$_code" in
    0) ;;
    3) fail "FM_LIVE_TYPESAFE was requested but TYPESAFE_API_KEY is not set in the environment or \$FM_HOME/.env" ;;
    *) fail "$label: fm-intake-classify exited $_code: $(cat "$TMP_ROOT/stderr")" ;;
  esac
  printf -v "$__out" '%s' "$_out"
}

out=''
classify out fix 'login sayfasında şifre yanlış girilince beyaz ekran geliyor, lütfen bu hatayı düzelt'
assert_contains "$out" 'kind=ship confidence=' "a fix request classifies as ship"
assert_contains "$(grep '^kind=' <<<"$out")" 'verdict=act' "a fix request clears the act threshold"
model=$(sed -n 's/^model=//p' <<<"$out")
[ -n "$model" ] || fail "no model id reported: $out"
pass "fix request: $(grep '^kind=' <<<"$out")"

classify out report 'bu haftaki pull requestleri incele ve bana kısa bir rapor yaz, henüz hiçbir şey değiştirme'
assert_contains "$out" 'kind=scout confidence=' "a report request classifies as scout"
assert_contains "$(grep '^kind=' <<<"$out")" 'verdict=act' "a report request clears the act threshold"
assert_equals "$model" "$(sed -n 's/^model=//p' <<<"$out")" "both answers come from the same model"
pass "report request: $(grep '^kind=' <<<"$out")"

export_request='tedarikçi (Suppliers) listesine dışa aktarma butonu ekle'
classify out overlap "$export_request" --area Suppliers --area Packaging --area declarations
assert_contains "$out" 'kind=ship confidence=' "an export-button request classifies as ship"
assert_contains "$out" 'surface=product_facing confidence=' "an export button is product facing"
assert_contains "$(grep '^surface=' <<<"$out")" 'verdict=act' "the surface call clears the act threshold"
assert_contains "$(grep '^teammate_overlap=' <<<"$out")" 'verdict=yes' "Suppliers among the teammate areas is an overlap"
assert_equals "$model" "$(sed -n 's/^model=//p' <<<"$out")" "the overlap answer comes from the same model"
pass "export button with Suppliers listed: $(grep '^surface=\|^teammate_overlap=' <<<"$out" | tr '\n' ' ')"

classify out no-areas "$export_request"
assert_contains "$out" 'kind=ship confidence=' "the same request still classifies as ship"
assert_contains "$(grep '^teammate_overlap=' <<<"$out")" 'verdict=no' "an empty teammate area list is never an overlap"
pass "export button with no areas: $(grep '^teammate_overlap=' <<<"$out")"

printf 'model: %s\n' "$model"
echo "# all fm-intake-classify-live-e2e tests passed"
