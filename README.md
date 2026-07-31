# firetrail

A density inspired set of compressors going at blazing speeds.

## TLDR

All benchmarks are done on my pc (Ryzen 7 7800X3D). Take them with a grain of salt.

Firetrail comes in three flavors, all built around the same idea: hash 8-byte words into a 512 KB lookup table, emit a 2-byte hash on a match, the raw word otherwise.

- **White** never updates its table. It's a static-dictionary codec: train a dictionary once (`--export`), deploy it everywhere (`--import`). Fastest of the three.
- **Orange** updates its table on every miss (last-write-wins). Adapts to any data, no dictionary needed.
- **Red** updates its table only when a slot's frequency count decays to zero. Slower, but the best dictionary trainer.

### On `silesia.tar` (mixed corpus, zbench, warm)

|                      | Encode     | Decode     | Ratio        |
| -------------------- | ---------- | ---------- | ------------ |
| White (trained dict) | ~4.67 GB/s | ~7.55 GB/s | ~23.4% saved |
| Orange               | ~3.17 GB/s | ~5.37 GB/s | ~35.2% saved |
| Red                  | ~1.57 GB/s | ~1.95 GB/s | ~34.4% saved |

### lz4 (for reference)

- **Speed:** ~0.89 GB/s encoding | ~5.76 GB/s decoding
- **Ratio:** High | ~52.4% saved on `silesia.tar`.

## Benchmark plot

![plot.png](./plot.png)

## Usage

### CLI Tool

```bash
firetrail {white|orange|red} [--encode | --decode] <input> <output> [--import <lut_file>] [--export <lut_file>]
```

The argument `<input>` or `<output>` can be replaced with `-` to stream from `stdin` or to `stdout` respectively.

`--import` preloads a 512 KB lookup table (dictionary); `--export` writes the table out after encoding. Typical white workflow:

```bash
# Train once (red makes the best dictionaries)
firetrail red --encode sample.log /dev/null --export dict.bin

# Deploy everywhere
firetrail white --encode app.log app.log.ftw --import dict.bin
firetrail white --decode app.log.ftw app.log --import dict.bin
```

### Benchmarks

```bash
zig build bench --release=fast -- data/silesia.tar
```

Cold runs use an empty table; warm runs use a dictionary trained by red on the input itself.
