# CORE-V investigation reports

Worked examples of how we investigate an RTL verification issue and what the
finished document looks like. Sixteen issues from the OpenHW CORE-V family,
each taken from a public GitHub issue to a disposition backed by evidence that
can be rerun.

**This repository is a demonstration of method, not a request for
contributions.** It exists so that anyone deciding whether to work with us can
read the actual output first: the reasoning, the evidence, the limits, and the
places where the answer is "unresolved".

## Read one report first

Start with [issue 1010](reports/rtl-triage-cv32e40p-1010.pdf). It is three
pages. It shows a coverage hole proven unreachable, the two proofs that
establish it, the anti-vacuity cover that shows the proofs are not trivially
true, the waiver text to apply, and a Limitations section stating what the
result does not establish.

Then read the [disposition register](reports/disposition-register.pdf) for all
sixteen at a glance.

## What is in every report

A fixed clause order, taken from published silicon errata and anomaly reports
(ARM, TI, Intel specification updates, NASA anomaly practice):

1. **Status** - issue, type, affected core and configuration, disposition,
   severity, agreement with any independent human record
2. **Description** - what was found and the mechanism
3. **Conditions** - what has to be true for the result to hold
4. **Implications** - what it means for a user of the core
5. **Action** - the waiver text, patch or test to apply
6. **Evidence** - every artefact, its path, and whether that file is present
7. **Limitations and scope** - what the result does *not* establish
8. **Provenance and measurement** - inputs, tool time, how it was produced

Severity prints as "Not assessed" where none was recorded. The generator does
not infer a severity from a disposition, and it does not write a clause it has
no data for. Absent data is stated as absent.

## The results

| Issue | Core | Title | Disposition | Upstream state (17 Sep 2026) | Report |
|---|---|---|---|---|---|
| [#1004](https://github.com/openhwgroup/cv32e40p/issues/1004) | cv32e40p | Interrupt during the first fetch after wake-up | Reachable, directed test supplied | **open, no replies** | [PDF](reports/rtl-triage-cv32e40p-1004.pdf) |
| [#1005](https://github.com/openhwgroup/cv32e40p/issues/1005) | cv32e40p | Outer loop ending inside the inner loop | Waiver, with a stated software rule | **open, no replies** | [PDF](reports/rtl-triage-cv32e40p-1005.pdf) |
| [#1006](https://github.com/openhwgroup/cv32e40p/issues/1006) | cv32e40p | Duplicate hardware-loop jump guard | Waiver, with a stated software rule | **open, no replies** | [PDF](reports/rtl-triage-cv32e40p-1006.pdf) |
| [#1007](https://github.com/openhwgroup/cv32e40p/issues/1007) | cv32e40p | Single-step with a stalled decode stage | Dead code, proven | **open, no replies** | [PDF](reports/rtl-triage-cv32e40p-1007.pdf) |
| [#1009](https://github.com/openhwgroup/cv32e40p/issues/1009) | cv32e40p | Nested hardware-loop end addresses too close together | Waiver, with a stated software rule | **open, no replies** | [PDF](reports/rtl-triage-cv32e40p-1009.pdf) |
| [#1010](https://github.com/openhwgroup/cv32e40p/issues/1010) | cv32e40p | Debug single-step inside a hardware loop | Dead code, proven | **open, no replies** | [PDF](reports/rtl-triage-cv32e40p-1010.pdf) |
| [#1011](https://github.com/openhwgroup/cv32e40p/issues/1011) | cv32e40p | Debug entry with no recorded cause | Dead code, proven | **open, no replies** | [PDF](reports/rtl-triage-cv32e40p-1011.pdf) |
| [#1012](https://github.com/openhwgroup/cv32e40p/issues/1012) | cv32e40p | Debug flush with an impossible single cause | Dead code, proven | **open, no replies** | [PDF](reports/rtl-triage-cv32e40p-1012.pdf) |
| [#1015](https://github.com/openhwgroup/cv32e40p/issues/1015) | cv32e40p | Operand-select combination in the ID stage | Dead code, proven | **open, no replies** | [PDF](reports/rtl-triage-cv32e40p-1015.pdf) |
| [#196](https://github.com/openhwgroup/cv32e40x/issues/196) | cv32e40x | Interrupt during single-step retired a handler instruction | Bug confirmed, fix verified | closed 2021-10-12 | [PDF](reports/rtl-triage-cv32e40x-196.pdf) |
| [#198](https://github.com/openhwgroup/cv32e40x/issues/198) | cv32e40x | CSR write slips through while debug halts the pipeline | Bug confirmed, fix verified | closed 2021-09-08 | [PDF](reports/rtl-triage-cv32e40x-198.pdf) |
| [#323](https://github.com/openhwgroup/cv32e40x/issues/323) | cv32e40x | zext.h wrongly rejected as illegal with the B extension (closed bug, replayed) | Bug confirmed, fix verified | closed 2021-11-25 | [PDF](reports/rtl-triage-cv32e40x-323.pdf) |
| [#333](https://github.com/openhwgroup/cv32e40x/issues/333) | cv32e40x | Reading a debug-only CSR outside debug mode must trap (closed bug, replayed) | Bug confirmed, fix verified | closed 2021-12-03 | [PDF](reports/rtl-triage-cv32e40x-333.pdf) |
| [#410](https://github.com/openhwgroup/cv32e40x/issues/410) | cv32e40x | Debug request at reset must halt the core before it runs (closed bug, replayed) | Bug confirmed, fix verified | closed 2023-01-06 | [PDF](reports/rtl-triage-cv32e40x-410.pdf) |
| [#558](https://github.com/openhwgroup/cv32e40x/issues/558) | cv32e40x | Does minstret count an mret executed in debug mode? (closed bug, replayed) | Bug confirmed, fix verified | closed 2022-08-04 | [PDF](reports/rtl-triage-cv32e40x-558.pdf) |
| [#993](https://github.com/openhwgroup/cv32e40x/issues/993) | cv32e40x | Does CV32E40X fetch its first instruction from boot+4? | Not reproduced | **open, no replies** | [PDF](reports/rtl-triage-cv32e40x-993.pdf) |

Ten of these issues are still open. The nine CV32E40P coverage holes were
filed in June 2024 and have had no replies since. CV32E40X #993 is also open;
we did not reproduce the reported behaviour, and the report says so rather than
calling it fixed.

The six closed CV32E40X issues were replayed blind against their pre-fix
revisions and then against the fix, to test the method against known answers.
Those fixes are the upstream authors' work, not ours.

Upstream state was checked on 17 September 2026 and will drift. None of these
reports has been submitted upstream, and none is endorsed by OpenHW.

## Method

Every result comes from open-source tools: sv2v, Yosys, SymbiYosys, Verilator,
z3, yosys-slang. No commercial licence is used or required, so any of it can be
rerun by anyone in the ecosystem.

The investigation is blind first: the issue title and body are read, the
property is written and run, and only afterwards is any existing human record
attached for comparison. Failed property iterations are kept and labelled
rather than deleted. A `prove` PASS is unbounded under the stated model, a
`bmc` PASS is bounded to its depth, and a `cover` PASS establishes reachability
only. Those three are never described as the same thing.

## What these documents are not

- Not a verification sign-off. Each one is an internal investigation record and
  states on every page that it requires engineering review.
- Not merged upstream. Nothing here has been accepted by OpenHW.
- Not a claim that any core is verified. Specific issues were dispositioned
  under specific configurations, named in each report.
- Not client work. These are public cores and public issues.

## Contact

Rivoryxa Technologies. If you have a coverage hole blocking a sign-off, or a
bug report nobody has reproduced, we would like to look at it.
