# firetrail

A density inspired set of compressors going at blazing speeds.

## TLDR

All benchmarks are done on my pc (Ryzen 7 7800X3D, `silesia.tar`). Take them with a grain of salt.

### White

White is a direct one-to-one implementation of `skim`, the fastest compression algorithm in the world.

- **Speed:** ~3.34 GB/s encoding | ~5.69 GB/s decoding
- **Efficiency:** Compresses 100MB in ~30 ms.
- **Ratio:** Low | ~35.5% saved on `silesia.tar`.

### lz4

- **Speed:** ~0.89 GB/s encoding | ~5.76 GB/s decoding
- **Efficiency:** Compresses 100MB in ~112 ms.
- **Ratio:** High | ~52.4% saved on `silesia.tar`.

## Benchmark plot

![plot.png](./plot.png)

## Usage

### CLI Tool

```bash
firetrail <white> [--encode | --decode] <input> <output>
```

The argument `<input>` or `output` can be replaced with `-` to stream from `stdin` or to `stdout` respectively.
