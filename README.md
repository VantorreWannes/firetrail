# firetrail

A density inspired set of compressors going at blazing speeds.

## TLDR

All benchmarks are done on my pc (Ryzen 7 7800X3D, CachyOS). Single-thread, end-to-end CLI runs (file in, file out, warm page cache); baselines are zstd v1.5.7 `--fast=5` and lz4 v1.10.0 `--fast=20`, both pinned to `-T1`. White runs use a 512 KB dictionary trained by red on the input itself (not counted in its size). These end-to-end numbers supersede the older in-memory ones. Take them with a grain of salt.

Firetrail comes in three flavors, all built around the same idea: hash 8-byte words into a 512 KB lookup table, emit a 2-byte hash on a match, the raw word otherwise.

- **White** never updates its table. It's a static-dictionary codec: train a dictionary once (`--export`), deploy it everywhere (`--import`). Fastest of the three.
- **Orange** updates its table on every miss (last-write-wins). Adapts to any data, no dictionary needed.
- **Red** updates its table only when a slot's frequency count decays to zero. Slower, but the best dictionary trainer.

## [silesia.tar](https://sun.aei.polsl.pl//~sdeor/index.php?page=silesia)

211,948,544 bytes

| Codec                | Config                  | Encode (GB/s) | Decode (GB/s) |     Ratio |
| -------------------- | ----------------------- | ------------: | ------------: | --------: |
| **firetrail White**  | warm (red-trained dict) |      **1.67** |          1.89 |     1.31× |
| **firetrail Orange** | cold                    |          1.54 |          1.78 |     1.54× |
| **firetrail Red**    | cold                    |          1.08 |          1.23 |     1.53× |
| zstd                 | --fast=5                |          0.69 |          1.66 | **2.06×** |
| lz4                  | --fast=20               |          0.98 |      **2.53** |     1.56× |

## [HDFS.log](https://www.kaggle.com/datasets/ayenuryrr/loghub-hdfs-hadoop-distributed-file-system-data)

1,577,982,906 bytes

| Codec                | Config                  | Encode (GB/s) | Decode (GB/s) |     Ratio |
| -------------------- | ----------------------- | ------------: | ------------: | --------: |
| **firetrail White**  | warm (red-trained dict) |      **2.72** |          2.57 |     2.19× |
| **firetrail Orange** | cold                    |          2.42 |          2.45 |     2.53× |
| **firetrail Red**    | cold                    |          1.76 |          1.86 |     2.43× |
| zstd                 | --fast=5                |          1.21 |          2.04 | **6.40×** |
| lz4                  | --fast=20               |          1.25 |      **2.96** |     4.53× |

## [enwik9](https://mattmahoney.net/dc/textdata.html)

1,000,000,000 bytes

| Codec                | Config                  | Encode (GB/s) | Decode (GB/s) |     Ratio |
| -------------------- | ----------------------- | ------------: | ------------: | --------: |
| **firetrail White**  | warm (red-trained dict) |      **1.55** |          1.87 |     1.27× |
| **firetrail Orange** | cold                    |          1.51 |          1.82 |     1.31× |
| **firetrail Red**    | cold                    |          1.02 |          1.22 |     1.35× |
| zstd                 | --fast=5                |          0.60 |          1.62 | **1.82×** |
| lz4                  | --fast=20               |          1.11 |      **2.79** |     1.26× |

## [enwik8](https://mattmahoney.net/dc/textdata.html)

100,000,000 bytes

| Codec                | Config                  | Encode (GB/s) | Decode (GB/s) |     Ratio |
| -------------------- | ----------------------- | ------------: | ------------: | --------: |
| **firetrail White**  | warm (red-trained dict) |          1.37 |          1.70 |     1.20× |
| **firetrail Orange** | cold                    |      **1.40** |          1.63 |     1.20× |
| **firetrail Red**    | cold                    |          0.96 |          1.14 |     1.24× |
| zstd                 | --fast=5                |          0.53 |          1.54 | **1.60×** |
| lz4                  | --fast=20               |          1.06 |      **2.29** |     1.12× |

## Findings

- White is the fastest encoder of the bunch everywhere: geomean `1.6x` faster than lz4 and `2.5x` faster than zstd across the four corpora (orange: `1.5x` / `2.3x`, red: `1.1x` / `1.6x`).
- Red and orange beat lz4's _ratio_ on enwik8/enwik9 while encoding faster (enwik9: red 742 MB vs. lz4 795 MB). On HDFS and silesia, lz4 stays smaller.
- lz4 still owns decode everywhere; white and orange both out-decode zstd everywhere; red doesn't.
- Memory is flat at ~15–20 MB RSS from 95 MiB to 1.5 GiB inputs — genuinely streaming.
- Caveat: enwik8 (95 MiB) nearly fits in the 7800X3D's 96 MB L3, so its numbers are flattering.

## Benchmark plot

![plot.png](./plot.png)

## Usage

### CLI Tool

```bash
firetrail {white|orange|red} [encode | decode] <input> <output> [--import <lut_file>] [--export <lut_file>]
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
