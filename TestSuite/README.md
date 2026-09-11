# W3C XForms 1.1 Test Suite (Edition 1) for XFormsKit

`XForms1.1/Edition1/` is the W3C XForms 1.1 Edition 1 test suite as
shipped in the XSLTForms repository (`testsuite/XForms1.1`), verbatim —
per-chapter test forms plus the `driverPages/` catalog (the
`driverPages/xml/XF11TestSuite*.xml` manifests are what the runner
reads). The suite is W3C material; see the W3C Document/Software
licenses. Two files the manifests reference are absent upstream
(4.5.3.a, H.3) and are reported as `missing`.

## Running

    make testsuite            # from the repository root (GNUstep)

or directly:

    cd Tools/xftestrun && make
    ./obj/xftestrun ../../TestSuite/XForms1.1/Edition1 [--chapter <n>] [--test 7.7.1.a]

The runner is a headless end-to-end harness: every test loads into a
real XFProcessor and lays out in a real XFFormView (GNUstep runs both
without a display). A generic interaction pass activates every trigger
once and types into every input; submissions run against a stub
transport that fails instantly for non-file URLs (the W3C echo servers
are long gone — which is exactly what the deliberately-bad-URL tests
expect to observe). A future iOS backend needs to supply only the two
build steps (processor + view) to reuse the whole harness.

## Verdicts

The suite was written for human judgment, so the runner automates the
forms' own conventions and leaves the rest for review:

- **pass** — the form's stated expectations were observed: every quoted
  string from its instruction labels appeared among the rendered VALUES
  (labels are excluded from the match target, or the instruction would
  satisfy itself), or one of the form's own xf:message texts was
  actually shown.
- **check** — quoted expectations exist but were NOT observed: a
  candidate fail. Review before believing it: instruction quotes are a
  heuristic (button names get quoted too), and Chapter 11 largely needs
  a live submission endpoint.
- **review** — ran cleanly, nothing auto-checkable (manual test).
- **error** — the document failed to load or the run raised.
- **missing** — the manifest links a file the suite does not contain.

`results.tsv` (one row per test) and `report.md` (per-chapter summary)
are the latest committed run. `overrides.tsv` pins human verdicts over
the automation: one line per test, `name<TAB>status<TAB>note`, status
`pass|fail|skip|na` (`skip` excludes the test from the run; `na` = not
applicable to this build). Overrides win over auto verdicts and are the
place to record reviewed judgments as chapters are worked through.
