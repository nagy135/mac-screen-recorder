# Recording startup measurements

Measured five sequential launches on this Apple Silicon Mac on 2026-10-27, after installing the instrumented release build. Each launch used `--measure-startup --smoke-test`, showed the normal countdown, recorded for three seconds after the native recording-start callback, and finalized successfully.

## Observed delay

| Measurement | Minimum | Median | Maximum |
| --- | ---: | ---: | ---: |
| App entry to first complete frame arrival | 3,516 ms | 3,561 ms | 3,893 ms |
| Visible countdown | 3,060 ms | 3,085 ms | 3,150 ms |
| Widget hidden to first complete frame arrival | 270 ms | 298 ms | 524 ms |
| Widget hidden to recording-start callback | 256 ms | 272 ms | 498 ms |

The delay after the widget disappears is measurable, but not constant. The first measurement was the slowest; the other four first-frame delays ranged from 270 to 300 ms. This does not establish a cold-launch or reboot bound.

| Run | Widget hidden → first frame | Widget hidden → recording confirmed | App entry → first frame |
| --- | ---: | ---: | ---: |
| 1 | 523.54 ms | 497.95 ms | 3,893.47 ms |
| 2 | 298.10 ms | 271.94 ms | 3,552.63 ms |
| 3 | 299.72 ms | 263.07 ms | 3,516.45 ms |
| 4 | 269.76 ms | 256.44 ms | 3,560.69 ms |
| 5 | 285.19 ms | 276.62 ms | 3,672.53 ms |

## Where the post-countdown time goes

| Stage after hiding | Minimum | Median | Maximum |
| --- | ---: | ---: | ---: |
| Explicit 150 ms compositor-settle sleep | 151.97 ms | 156.05 ms | 159.43 ms |
| Destination/output/stream setup and diagnostic observer attachment | 71.47 ms | 79.60 ms | 115.98 ms |
| Capture request → first complete frame arrival | 45.88 ms | 62.45 ms | 248.14 ms |

The countdown sleeps for one second per number; task scheduling can make those waits slightly longer. After hiding, it intentionally waits another 150 ms before preparing the output and asking macOS to start capture. Preparing the output during the countdown could remove most of the measured setup stage from the visible gap, but these diagnostics leave startup behavior unchanged.

Before the countdown, display discovery took 26.24–44.58 ms. Initial app setup and the already-granted permission check took 107.09–260.90 ms from entry to `main()`.

## What the timestamps mean

- All event intervals use monotonic `DispatchTime` uptime, so clock changes do not affect them.
- `process_entry` starts in the app's `main()`; Finder/LaunchServices and process loading before that point are not measured.
- `countdown_hidden` is when the app orders its panel off screen, not a photometric observation of a display refresh.
- `first_complete_frame_arrived` is the first valid `.complete` screen sample received by the diagnostic stream observer. Its callback entry timestamp is taken on the sample queue before hopping to the main actor.
- `recording_output_started` is the native recording output's start callback, measured at callback entry. The red dot is updated from this event; it does not assume a fixed startup delay.
- `start_capture_returned` is logged independently. Returning from the asynchronous start request is not used as a substitute for either first-frame arrival or writer confirmation.

Apple documents [asynchronous stream startup](https://developer.apple.com/documentation/screencapturekit/scstream/startcapture(completionhandler:)), [stream sample delivery](https://developer.apple.com/documentation/screencapturekit/scstreamoutput), and [recording lifecycle callbacks](https://developer.apple.com/documentation/screencapturekit/screcordingoutputdelegate).

## Limits and reproduction

Five runs are a small local sample, not a guaranteed latency range. Permission prompts, system load, display configuration, and other recording sessions can produce longer waits. The opt-in observer and logging add some diagnostic work; normal launches do not attach the observer or emit these timing events. First sample arrival and recording-start confirmation do not measure when that sample is committed to disk.

```sh
./scripts/install.sh
"/Applications/Mac Screen Recorder.app/Contents/MacOS/MacScreenRecorder" --measure-startup --smoke-test 2> dist/startup-timing.log
```

Repeat the last command to collect independent runs. `STARTUP_TIMING` lines contain stage names and `elapsed_ms` JSON fields. The command saves a normal MP4 in `~/Documents/Videos` and opens Finder after saving. The benchmark videos and raw local diagnostic logs are not committed to the repository.
