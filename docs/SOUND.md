# Sound implementation and verification boundaries

The sound board runs an MC6809-compatible CPU, the revision-specific timer/VIA
logic, and an ES5506 functional model. Clock enables retain the board's nominal
2 MHz CPU and 16 MHz ES input rates; host memory latency must not be hidden by
changing those clocks. Shared DDR requests hold their payload until completion.
The CPU may overlap an inactive phase with a memory response, but both active
E/Q edges remain gated by readiness. This does not increase its nominal rate.

Program ROM uses a registered, two-way cache with 512 eight-byte sets (8 KiB).
Each way stores the complete physical tag and one qword in synchronous M10Ks.
This matters because the fixed and banked 6809 regions can share an index; one
line from each region can now remain resident together. A hit still reads at T0,
compares/selects at T1 and acknowledges at T2. Only misses enter shared DDR
arbitration, where at most four additional sample grants may precede SOUND.
Replacement is invalid-first, then deterministic one-bit LRU. Cache capacity is
an FPGA latency absorber, not a claim about storage inside the original board.

## Primary reference

ENSONIQ OTTO Specification Revision 2.3:
https://gjcp.net/pdf/es5506.pdf

The manufacturer scan is the primary functional reference. MAME remains useful
for software behavior and independent comparisons, not as proof of physical
board timing. Its implementation and board configuration are available at:

- https://github.com/mamedev/mame/blob/master/src/devices/sound/es5506.cpp
- https://github.com/mamedev/mame/blob/master/src/mame/itech/itech32.cpp

The datasheet is not redistributed here. Preserve the MAME and CPU attributions
in `CREDITS.md` when adapting this implementation.

## ES5506 datapath

The engine processes one voice per 16 ES clock enables. Interpolation, four
filter poles, envelopes and volume multiplication occupy registered stages in
the faster FPGA carrier domain. Running, stopped and cache-underrun paths have
the same terminal phase; a host access must leave enough time for the next slot.
This implementation continues filter and envelope processing for stopped voices,
but does not advance their address or contribute audible output. The manufacturer
text is internally ambiguous here: its CPU-write warning qualifies active voices
as not stopped, while the later per-sample algorithm has no STOP guard. Continuing
the envelope matches the established compatibility model and remains an explicit
interpretation rather than a measured-silicon claim.

The selected arithmetic interpretations are explicit:

| Operation | Representation/policy |
| --- | --- |
| Address accumulator | All 21 integer and 11 fractional bits retained |
| Interpolation | Upper nine fractional bits, ACCUM[10:2]; signed16.1 result |
| Six filter histories | Signed 32-bit internal guard retention; host reads and writes expose the documented signed 18-bit register view |
| Filter arithmetic | Exact signed 32-by-12 products; division truncates toward zero; intermediate poles are not narrowed to the host-register width |
| Panning input | Arithmetic O4/2 with the internal guard bits retained |
| Volume | Full unsigned 9-bit implicit mantissa multiply, then exponent shift |
| Companding | All 16 sample-bus bits consumed; narrow-ROM padding belongs to wiring |
| Mixing | Six independent 23-bit stereo accumulators, clipped individually to 20 bits |

The printed page 9 filter-mode table conflicts with the page 34 diagram for two
coefficient selections. This implementation follows the table. The signed
32-bit history width and truncation policy match the established compatibility
model and deterministic game traces; the manufacturer specification exposes an
18-bit register view and requires at least 18-bit accuracy, but does not establish
an 18-bit internal wrap after every pole. A narrow-wrap implementation produced
large discontinuities in Time Killers' high-pass voice effects, while retaining
guard bits removed them without changing the already-correct low-pass effect.
This is compatibility evidence, not a claim of a measured silicon width.
Extreme guard-bit overflow and reset sub-phases remain documented interpretations.
In particular, 23-bit accumulation wraps at that storage width before the
documented per-channel 20-bit output clipping.

There is one canonical channel store. CR.CA selects a channel; the scalar stereo
ports alias channel 0 rather than folding all voices through another mixer.
The ITech32 board consumes that pair and performs its established left/right
swap and MiSTer conversion. MAME applies the ITech32 route gain in a
floating-point mixer. The MiSTer boundary instead normalizes the complete signed
20-bit range into signed 16 bits before the framework mixer; applying the route
gain before that fixed-width boundary hard-clips otherwise valid ES5506 output.
This preserves the waveform and leaves volume adjustment to the downstream
MiSTer mixer. Channel 0 selection is a compatibility assumption for the
supported boards, not a substitute for a traced physical schematic.

PAGE 40 writes target the same channel accumulators used by normal voices.
The implementation does not invent a test-mode freeze: a write after the scan's
clear can contribute to its next complete output. Exact host-write/clear collision
phase remains an interface interpretation. Undefined CA 6/7 are silent.

IRQV reads release the global interrupt immediately. The causative voice's CR.IRQ
clears when that voice next completes processing, including the stopped path.
Sample-cache underrun does not prematurely consume that deferred clear.
FILTCOUNT runs modulo 8 across ECOUNT 0 and ECOUNT writes, following the envelope
algorithm; ECOUNT gates ramps, not the slow-ramp divider itself.

## FPGA interface abstractions

The model exposes native parallel PCM and held request/acknowledge memory ports.
It is not a pin-compatible ES5506 replacement. Physical serial clocks/data pins,
single/dual-chip DRAM strobes and host sound-memory DMA are not implemented.
Serial-control registers retain their programmed values, but raw PCM delivery is
not a simulation of an external DAC's bit clock or electrical behavior.

PAR byte-zero reads snapshot the prior 10-bit result and start or restart the
documented conversion sequence. The converter asserts discharge for exactly
4,096 subsequent 16 MHz enable events, then samples a semantic comparator level
once per four enables until it trips or the result saturates at `0x3ff`. The raw
comparator boundary uses two synchronizer flops before polarity normalization,
and discharge polarity is explicit. The current ITech32 top-level holds the raw
comparator at its inactive level and does not route a physical POT pin. External
RC values, board polarity and analogue threshold behavior therefore remain open;
the implemented digital sequence does not claim those physical properties.

Host byte latches, register masks and interrupt side effects are functional.
Host requests are serialized at voice transaction boundaries to preserve coherent
RAM rows. A bounded exception permits side-effect-free reads and envelope writes
for a different voice during interior engine states. A fully assembled same-voice
ECOUNT-zero write may cancel the pending terminal envelope update while preserving
the already-computed PCM contribution. Exact silicon DTACK phase, the three-voice
in-flight pipeline, and unprotected live register-write collisions are not
reproduced. Tests of the
documented stop-ramp/wait/reprogram sequence do not prove those collision cases.

DDR cache underrun is an FPGA integration condition, not a documented ES feature.
It preserves output cadence and holds that voice's complete state, but contributes
zero until the exact source words are resident. Replaying a prior contribution is
deliberately forbidden because it may encode an older sample bank, volume,
coefficient or filter history. STOP-to-RUN writes retain the normal host-register
completion path and only prioritize the existing urgent prefetcher; cache
readiness never stretches a CONTROL write. A fixed output strobe alone therefore
does not prove correct musical time: sample starvation and sound-CPU service must
also be checked.
The concurrent voice-prefetch RAM port carries a registered read/write collision
flag and rereads the held row before consuming it. It must not rely on the
behavioral simulator's old-data result for a physical mixed-port collision.

## Reproducible ROM-free checks

See `sim/README.md` and `python3 sim/run.py --list`. The specification-oriented
tests cover mathematical helper vectors, actual engine/history readback,
register masks and byte protocols, looping, envelopes, stacked IRQs, native
host/voice deadlines, all six channel outputs, and PAGE 40 shared-store behavior.
The checkers use authored samples and independent integer arithmetic. Filter
tests also exercise values outside the signed 18-bit host range, exact split
multiplier reconstruction, truncation of negative quotients, and the guarded
O4-to-volume handoff so a later optimization cannot silently restore pole wrap.

These tests deliberately distinguish documented behavior from interpretations
and interface abstractions. They do not establish bit-perfect silicon equivalence
or full-game audio fidelity. Real-game comparisons, captures, generated reports,
ROM-derived stimulus and fitted timing results belong outside this source tree.
