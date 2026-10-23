# FTPunk reference project audit

The reference at `reference_project/ftpunk` is a small JavaScript/Web Bluetooth ramp-test application. This audit covers commit `f8daa4e5da3e5f00f24fffae79ee514b8ac041ac`. The working tree was clean when inspected. Its MIT license permits reuse subject to retaining the notice in reused or substantially derived code.

## Existing functionality

| File | Functionality |
| --- | --- |
| `js/trainer.js:17` | Discover FTMS trainer, connect, subscribe to Indoor Bike Data and Control Point responses, and request control. |
| `js/trainer.js:53` | Encode target power as opcode `0x05` followed by two little-endian bytes. |
| `js/trainer.js:66` | Decode optional trainer fields by flags and maintain power, cadence, and speed. |
| `js/heartRateMonitor.js:21` | Select the 8-bit or 16-bit heart-rate representation from flags. |
| `js/ramp_test.js:18` | Wait for cadence, warm up, run a timed ramp, detect low cadence, estimate FTP, and lower the target for cooldown. |
| `main.js:24` | Read rider preset and warm-up settings and start the test. |
| `js/ui.js:45` | Present an FTP range and best-minute power. |

There is no independent Cycling Power pedal adapter, local session persistence, export, reconnect state machine, or test suite in the supplied source. The reference records trainer power, so using its calculation unchanged would not establish that the result came from the Assioma pedals.

## Trainer message decoding

The parser correctly uses little-endian fields, reads instantaneous speed only when bit 0 is clear, scales speed by 1/100 and cadence by 1/2, and sign-extends instantaneous power. Its running cursor is the right general approach for optional fields. The variable `flag_more_data` actually means that instantaneous speed is present; rename it during the port to avoid reversing its meaning.

The resistance cursor step at `trainer.js:96` needs special attention: it skips two bytes. The current Bluetooth GATT supplement defines Indoor Bike Data Resistance Level as a one-byte value. This shifts the power offset when the resistance flag is present in a standard-layout packet. Confirm the actual Suito-T firmware layout; isolate a documented device exception if captures demonstrate a different layout. [Bluetooth GATT supplement, section 3.139](https://btprodspecificationrefs.blob.core.windows.net/gatt-specification-supplement/GATT_Specification_Supplement.pdf)

| Finding | Source | Required change |
| --- | --- | --- |
| The full backing buffer is read, ignoring the DataView offset and length. | `trainer.js:67` | For JavaScript reuse, respect `byteOffset` and `byteLength`. In Swift, decode only the provided characteristic `Data`. |
| Reads and cursor skips have no bounds checks. Undefined bytes can become zero through bitwise operations. | `trainer.js:69–106` | Validate flags, every selected field, and the complete packet before committing decoded measurements. |
| Retained fields are emitted without their own ages. A packet without power can republish an older value. | `trainer.js:108–113` | Separate the latest display snapshot from new measurement events and maintain field-specific timestamps. |
| Multi-notification records have no assembly lifecycle. | `trainer.js:66–115` | Parse each value independently and bound record assembly using FTMS semantics; do not count repeated cached fields as new samples. |
| The response handler reads only opcode and request opcode, then discards them. It ignores the result byte. | `trainer.js:38–42` | Parse response/request/result, match the pending transaction, and surface rejection/timeouts. |
| Target writes have no capability/range validation or application-level completion tracking. | `trainer.js:53–60` | Read capabilities/range, serialize procedures, and await the corresponding indication. |
| No start/stop procedure or loss-of-control handling is implemented. | `trainer.js` | Verify the Suito sequence and handle machine status and connection changes. |

FTMS control completion is distinct from GATT write acknowledgement. Subscribe to indications before sending procedures and handle response results and control-permission loss explicitly. [Bluetooth FTMS specification](https://www.bluetooth.org/DocMan/handlers/DownloadDoc.ashx?doc_id=423422)

### Synthetic packet experiments

The unmodified `Trainer` class body was evaluated in a JavaScript VM, omitting only the unused `parseUInt24` import and module export syntax. Six calls to its actual `_handleBikeData` method produced the observations below. These are synthetic notifications, not captures from the user's hardware.

| Input or condition | Expected interpretation | Observed reference behavior |
| --- | --- | --- |
| `44 00 C4 09 B4 00 C8 00` | 25 km/h, 90 rpm, 200 W | Correct. |
| `40 00 00 00 F6 FF` | Signed power of −10 W | Correct signed watts; prior cadence remains cached. |
| Speed-only `00 00 C4 09` after the prior packet | New speed, no new power measurement | Retains −10 W with no freshness marker. |
| Truncated `40 00 00 00` | Reject missing power bytes | Sets power to 0 W. |
| `60 00 00 00 05 C8 00` | One-byte resistance followed by 200 W | Reads 0 W because its cursor skips two resistance bytes. |
| Backing bytes `00 00 40 00 00 00 C8 00`, DataView offset 2 and length 6 | 200 W, 0 km/h | Reads 0 W and 0.64 km/h from the backing-buffer prefix. |

The Suito's real resistance-field layout and the pedals' total-power/cadence behavior still require hardware validation. The synthetic results establish decoder behavior only.

## Ramp execution and analysis

| Finding | Source | Consequence and plan |
| --- | --- | --- |
| Presets are 100 W plus 5 W/12 s, and 50 W plus 5 W/20 s. | `ramp_test.js:11–13,47–49` | Preserve them as 25 W/min and 15 W/min versioned presets. |
| Warm-up guidance says 50% of FTP, but the UI only accepts watts and switches between 100 W and 75 W defaults. | `main.js:45–58`, `index.html:59–62` | Add current/historical/manual FTP selection and derive warm-up watts at 50%, preserving a manual override. The reference does not calculate this percentage itself. |
| A one-second callback increments elapsed time and samples the latest cached power. | `ramp_test.js:28–29,56` | Callback delays change timing, and dropouts can duplicate stale power. Use monotonic deadlines and timestamped sensor data. |
| Ramp target writes are launched without awaiting results. | `ramp_test.js:44,49` | The schedule can progress despite failed control; add acknowledged command tracking and lateness handling. |
| A single trainer cadence below 45 rpm ends the test. | `ramp_test.js:52–54` | Use fresh pedal cadence and sustained detection. Separate exhaustion from missing data. |
| Finish runs before that tick's sample is appended. | `ramp_test.js:52–56` | The scored endpoint and sample membership are ambiguous. Define an exact time boundary before analysis. |
| A recording shorter than 60 samples still receives an FTP estimate. | `ramp_test.js:81–84` | Require a complete valid 60-second measurement window. |
| The algorithm selects the best 60 values, while the result text says “last minute.” | `ramp_test.js:69–89`, `ui.js:51` | Label it best continuous 60 seconds and display the actual interval. |
| Code calculates 72–77%; information text says 72–75%. | `ramp_test.js:87–88`, `index.html:76` | Standardize result labels, factors, and persisted algorithm version. |
| Engine methods directly call UI methods. | `ramp_test.js` | Move workout behavior into a domain state machine whose events drive presentation. |
| Start is enabled after trainer connection without readiness validation or a start guard. | `ui.js:36`, `main.js:24–35` | Require trainer control and fresh pedal data; allow one active session only. |
| Restart reloads the page; the wait-for-pedaling loop has no cancellation or timeout. | `main.js:37–38`, `ramp_test.js:61–64` | Add explicit cancel, finish, teardown, and session recovery. |

`js/uint24.js` provides a little-endian UInt24 helper but is unused by the trainer parser, which only skips distance. The heart-rate representation handling is useful, but its direct DOM mutation and unchecked reads should become a separate bounded decoder.

## Reuse decision

Port the protocol intent, two ramp definitions, optional heart rate, and best-minute result concept into Swift. Use the JavaScript decoder as an auditable reference, with the packet cases above as regression inputs. Rebuild transport/lifecycle handling and timing/analysis around native APIs and explicit state. Retain the reference MIT attribution in derived code.

The next implementation task is an iPhone hardware prototype that discovers both devices, captures their actual GATT values and capabilities, verifies control responses and stop behavior, and establishes pedal totals before building the full test experience.
