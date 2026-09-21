# Live intake-classification verdicts, 2026-09-21, commit aeac352

Driven against the real `https://api.typesafe.ai/v1/systemone` with the operator's `TYPESAFE_API_KEY` exported for one shell; model answered as `jev-1.13.0`; act threshold 0.70, overlap threshold 0.70. Areas listed = `--area Suppliers --area Packaging --area declarations`.

| Request (paraphrased) | kind | surface | overlap, areas listed | overlap, no areas | Input tokens |
| --- | --- | --- | --- | --- | --- |
| Fix the white screen after a wrong password on the login page | ship 1.0 act | product_facing 1.0 act | 0.09 no | 0.04 no | 922 / 905 |
| Review this week's pull requests and write a short report, change nothing yet | scout 1.0 act | mixed_or_unclear 0.99 act | 0.04 no | 0.04 no | 921 / 904 |
| The CI lint step takes ten minutes, add a cache and speed it up | ship 1.0 act | internal_tooling 1.0 act | 0.14 no | 0.04 no | 917 / 900 |
| Add an export button to the Suppliers list | ship 1.0 act | product_facing 0.99 / 1.0 act | 0.89 yes | 0.04 no | 915 / 898 |

Adversarial cases:

| Case | kind | surface | overlap |
| --- | --- | --- | --- |
| Export button on Suppliers, only Packaging and declarations listed | ship 1.0 act | product_facing 0.99 act | 0.20 no |
| Thread ending in "tamam, merge et" with an open green PR in context | answer_or_instruction 1.0 act | product_facing 0.42 ask | 0.04 no |
| Options message addressed to the captain ("Hangisini istersin?") | decision 0.94 act | internal_tooling 0.95 act | 0.04 no |
| Request on stdin, key from `$FM_HOME/.env` with the environment key unset | ship 1.0 act | product_facing 1.0 act | 0.04 no |

Guards driven against the real API:

- Invalid key: HTTP 401, exit 4, the API's authentication_error body on stderr, empty stdout, the key string absent from all output, nothing written under FM_HOME.
- Absent key: exit 3 with `not measured: TYPESAFE_API_KEY is not set`, no request made.
- `FM_LIVE_TYPESAFE=1 bash tests/fm-intake-classify-live-e2e.test.sh`: all four cases passed, model `jev-1.13.0`, key absent from guard output.

Every request answered in about one second and left FM_HOME empty. Every verdict matched the intended label and agrees with the record in docs/verification/intake-classify.md.
