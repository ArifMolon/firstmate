# Intake classification verification

Audience: maintainer verification.

This record supports the opt-in `bin/fm-intake-classify.sh` contract owned by [`../configuration.md`](../configuration.md) ("Intake classification") and the questions, model pin, and thresholds in [`../../bin/fm-intake-questions.json`](../../bin/fm-intake-questions.json).
It records only facts that must be re-established when the typesafe.ai model, its API, or the shipped questions change.
The captain's trial requests and labels stay out of the repository; the samples below are synthetic.

## The API the tool depends on

The request and response shapes, error statuses, and aliases are those recorded in [`dispatch-resolve.md`](dispatch-resolve.md) ("The API the tool depends on"); this tool adds one `noul` question, which returns `{noul}` with no confidence field.
Verified 2026-09-21 that a `jev-1.13.0` request answers as `jev-1.13.0`, so the pin resolves to the version the thresholds were measured on.

## Live verdicts

Run 2026-09-21 with `FM_LIVE_TYPESAFE=1 bash tests/fm-intake-classify-live-e2e.test.sh`, the key exported from a private env file for that one shell, model pinned at `jev-1.13.0`, act threshold 0.70, overlap threshold 0.50.

```console
$ FM_LIVE_TYPESAFE=1 bash tests/fm-intake-classify-live-e2e.test.sh
ok - fix request: kind=ship confidence=1.0 verdict=act
ok - report request: kind=scout confidence=1.0 verdict=act
model: jev-1.13.0
# all fm-intake-classify-live-e2e tests passed
```

Four synthetic Turkish requests run the same day through the tool directly, each with a one-line product context and the areas `Suppliers`, `Packaging`, and `declarations`:

| Request (paraphrased) | kind | surface | teammate_overlap | Input tokens | Wall time |
| --- | --- | --- | --- | --- | --- |
| Fix the white screen after a wrong password on the login page | ship 1.0 act | product_facing 0.99 act | 0.09 no | 927 | 812 ms |
| Review this week's pull requests and write a short report, change nothing yet | scout 1.0 act | mixed_or_unclear 0.99 act | 0.06 no | 926 | 781 ms |
| The CI lint step takes ten minutes, add a cache and speed it up | ship 1.0 act | internal_tooling 1.0 act | 0.11 no | 928 | 789 ms |
| Add an export button to the Suppliers list | ship 1.0 act | product_facing 1.0 act | 0.9 yes | 920 | 758 ms |

Every verdict matched the intended label, and every Choice cleared the act threshold.
Wall time includes the two local `jq` passes around the request; the request itself is about 1,000 input tokens, which at the published $0.042 per million input tokens is effectively free.

## Offline behavior

`tests/fm-intake-classify.test.sh` drives the public interface with a fake `curl` that records argv, the request body, the header read from file descriptor 3, whether the secret reached its environment, and the canned response headers, and answers one canned response per call.
It proves the absent key exits 3 with the explicit `not measured` line and never invokes `curl`, a `.env` key turns the tool on, and the environment wins over it.
It proves the key is absent from the child environment, never appears on `curl` argv, stdout, or stderr, and arrives only as the bearer header on the descriptor.
It proves the request uses the fixed endpoint, the twenty-second timeout, the pinned model unless `--model` overrides it for that call, carries `messages` oldest first with the request last, `context`, and `teammate_areas`, and sends the three questions verbatim from the questions file.
It proves the verdict mapping at, above, and below the act and overlap thresholds including the near-threshold marker, the `--json` output, exit 4 with the status and body on a 401 and a 422 without a retry, exactly one retry on a 429 that waits for `Retry-After` and on a 529 without one, exit 4 on a transport failure or an incomplete answer set with no guessed answer, and that nothing is written under `state/` or `data/`.

```console
$ bash tests/fm-intake-classify.test.sh | tail -1
# all fm-intake-classify tests passed
```

Rerun the live guard after a model release or a questions change, and refresh the table above from the tool's own output.
