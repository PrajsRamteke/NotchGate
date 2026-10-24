# voice-accuracy

Measures how accurately Apple's on-device speech recognition hears **your** voice, to
decide whether it's good enough for Notch Voice. Developer tool only: it isn't part of
the app and doesn't ship.

Everything runs on your Mac. There's no Anthropic login, no API key, and audio never
leaves the machine. The only network use is Apple downloading its speech model once.

Needs macOS 26 or later.

## Run it

```bash
cd Scripts/voice-accuracy
swift run voice-accuracy record    # read the 20 sentences aloud (Enter to start / stop)
swift run voice-accuracy test      # score every engine on your clips
```

The first `record` asks for microphone access for **voice-accuracy**. Clips go to
`clips/` (git-ignored). Already-recorded sentences are skipped, so you can quit with `q`
and carry on later. Delete a clip to record it again.

Speak the way you normally would when dictating a prompt. Use your usual mic and room.

## Options

| Option | What it does |
| --- | --- |
| `--locale en-IN` | Recognizer language and accent. Defaults to your Mac's region. |
| `--vocab vocabulary.txt` | Hint words (product names, code terms), like a personal dictionary. |
| `--compare wispr.txt` | Also score another tool's output: one line per sentence, same order. |
| `--legacy` | Add the older recognizer that macOS 14–15 users would get (asks for Speech Recognition access). |
| `--sentences FILE` / `--clips DIR` | Use your own sentences or clip folder. |

To compare with Wispr Flow, dictate each sentence from `sentences.txt` into a text editor
with Wispr Flow and save the results as `wispr.txt`, one line per sentence in the same
order. Then run `swift run voice-accuracy test --compare wispr.txt`.

## Reading the score

Accuracy is `1 − word error rate`: missing, extra and wrong words each count as one
error, against the sentence you were shown. Case and punctuation are ignored, and number
words match digits ("four" = "4"). The scoring is strict, so "code base" vs "codebase"
counts as wrong. Each transcript is saved to `results.csv` so you can see where each
engine slipped.

Wispr Flow rewrites what you say (removes fillers, rephrases), which can lower its
word-level score even when the text reads well. Turn its clean-up off for a fair
comparison.
