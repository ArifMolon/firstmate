# Intake classification verification

Audience: maintainer verification.

This record supports the opt-in `bin/fm-intake-classify.sh` contract owned by [`../configuration.md`](../configuration.md) ("Intake classification") and the questions, model pin, and thresholds in [`../../bin/fm-intake-questions.json`](../../bin/fm-intake-questions.json).
It records only facts that must be re-established when the typesafe.ai model, its API, or the shipped questions change.
The captain's trial requests and labels stay out of the repository; the samples below are synthetic.

## The API the tool depends on

The request and response shapes, error statuses, and aliases are those recorded in [`dispatch-resolve.md`](dispatch-resolve.md) ("The API the tool depends on"); this tool adds one `noul` question, which returns `{noul}` with no confidence field.
Verified 2026-09-21 that a `jev-1.13.0` request answers as `jev-1.13.0`, so the pin resolves to the version the thresholds were measured on.

## Live verdicts

The live guard `tests/fm-intake-classify-live-e2e.test.sh` covers `kind`, `surface`, and `teammate_overlap`: a fix request and a report request for `kind`, and an export-button request for a Suppliers list run once with Suppliers among the teammate areas and once with no areas for `surface` and `teammate_overlap`.
The `surface` and `teammate_overlap` wording and the 0.70 overlap threshold were revised on 2026-09-21 after review; the `kind` question is unchanged from the trial.

Measured 2026-09-21 on commit `158236d1`, which carries the revised questions, by the review phase of the pipeline run that produced that commit, with the key exported for that one shell, model pinned at `jev-1.13.0`, act threshold 0.70, overlap threshold 0.70.
The guard at that commit asserted only the two `kind` cases; the `surface` and `teammate_overlap` cases were added to it afterwards and were exercised in the same session by running the tool directly, as the table below records.

```console
$ FM_LIVE_TYPESAFE=1 bash tests/fm-intake-classify-live-e2e.test.sh
ok - fix request: kind=ship confidence=1.0 verdict=act
ok - report request: kind=scout confidence=1.0 verdict=act
model: jev-1.13.0
# all fm-intake-classify-live-e2e tests passed
```

Four synthetic Turkish requests run through the tool directly in that session, each twice: with `--area Suppliers --area Packaging --area declarations`, and with no area.

| Request (paraphrased) | kind | surface | overlap, areas listed | overlap, no areas | Input tokens |
| --- | --- | --- | --- | --- | --- |
| Fix the white screen after a wrong password on the login page | ship 1.0 act | product_facing 1.0 act | 0.09 no | 0.04 no | 941 / 924 |
| Review this week's pull requests and write a short report, change nothing yet | scout 1.0 act | mixed_or_unclear 0.99 act | 0.04 no | 0.04 no | 940 / 923 |
| The CI lint step takes ten minutes, add a cache and speed it up | ship 1.0 act | internal_tooling 1.0 act | 0.16 no | 0.04 no | 942 / 925 |
| Add an export button to the Suppliers list | ship 1.0 act | product_facing 1.0 act | 0.91 yes | 0.04 no | 934 / 917 |

Every verdict matched the intended label, every Choice cleared the act threshold, and the export-button request answered `yes` only when Suppliers was among the listed areas, which is the behaviour the revised wording exists to guarantee.
On the author's 18-request trial set the revised overlap Noul answered 0.87 on the two requests that touched a listed area, at most 0.56 on requests that touched none, and 0.04 to 0.05 with an empty area list; the earlier 0.50 cut sat inside a noisy 0.44 to 0.56 band, and 0.70 separates the two groups cleanly, which is why `thresholds.overlap` is 0.70.
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

Rerun the live guard after a model release or a questions change, and refresh the console block and table above from its output; the next keyed run is the first to print the guard's own `surface` and `teammate_overlap` lines.
