# Intake classification verification

Audience: maintainer verification.

This record supports the opt-in `bin/fm-intake-classify.sh` contract owned by [`../configuration.md`](../configuration.md) ("Intake classification") and the questions, model pin, and thresholds in [`../../bin/fm-intake-questions.json`](../../bin/fm-intake-questions.json).
It records only facts that must be re-established when the typesafe.ai model, its API, or the shipped questions change.
The captain's trial requests and labels stay out of the repository; the samples below are synthetic.

## The API the tool depends on

The request and response shapes, error statuses, and aliases are those recorded in [`dispatch-resolve.md`](dispatch-resolve.md) ("The API the tool depends on"); this tool adds one `noul` question, which returns `{noul}` with no confidence field.
Verified 2026-09-21 that a `jev-1.13.0` request answers as `jev-1.13.0`, so the pin resolves to the version the thresholds were measured on.

## Live verdicts

The `kind` question is unchanged since the run below; the `surface` and `teammate_overlap` wording and the overlap threshold were revised on 2026-09-21 after review, so the guard's console output and the table need a fresh keyed run before they describe the shipped questions.

Run 2026-09-21 with `FM_LIVE_TYPESAFE=1 bash tests/fm-intake-classify-live-e2e.test.sh`, the key exported from a private env file for that one shell, model pinned at `jev-1.13.0`, act threshold 0.70, against the `kind` question as shipped:

```console
$ FM_LIVE_TYPESAFE=1 bash tests/fm-intake-classify-live-e2e.test.sh
ok - fix request: kind=ship confidence=1.0 verdict=act
ok - report request: kind=scout confidence=1.0 verdict=act
model: jev-1.13.0
# all fm-intake-classify-live-e2e tests passed
```

The revised `surface` and `teammate_overlap` wording was re-measured the same day by the author on the 18-request trial set that set the thresholds: the overlap Noul answered 0.87 on the two requests that touched a listed area, at most 0.56 on requests that touched none, and 0.04 to 0.05 with an empty `teammate_areas` list.
The earlier 0.50 overlap cut sat inside a noisy 0.44 to 0.56 band on that set; 0.70 separates the two groups cleanly, which is why `thresholds.overlap` is 0.70.
The previous wording had named the areas inside the Noul criteria, so a request touching one of them answered `yes` even with an empty area list; the revised wording defers to `teammate_areas` alone.

One request is about 1,000 input tokens, which at the published $0.042 per million input tokens is effectively free, and answers in under a second.

## Offline behavior

`tests/fm-intake-classify.test.sh` drives the public interface with a fake `curl` that records argv, the request body, the header read from file descriptor 3, and whether the secret reached its environment, and answers one canned response per call.
It proves the absent key exits 3 with the explicit `not measured` line and never invokes `curl`, a `.env` key turns the tool on, and the environment wins over it.
It proves the key is absent from the child environment, never appears on `curl` argv, stdout, or stderr, and arrives only as the bearer header on the descriptor.
It proves the request uses the fixed endpoint, the twenty-second timeout, and the pinned model, carries `messages` oldest first with the request last, `context`, and `teammate_areas`, and sends the three questions verbatim from the questions file.
It proves the verdict mapping at, above, and below the act and overlap thresholds, exit 4 with the status and body on a 401, 422, 429, or 529 with exactly one call and no retry, exit 4 on a transport failure or an incomplete answer set with no guessed answer, and that nothing is written under `state/` or `data/`.

```console
$ bash tests/fm-intake-classify.test.sh | tail -1
# all fm-intake-classify tests passed
```

Rerun the live guard after a model release or a questions change, and refresh the console output above from the tool's own output; the pending run for the revised wording is the first such refresh.
