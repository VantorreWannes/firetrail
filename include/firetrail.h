#ifndef FIRETRAIL_H
#define FIRETRAIL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum firetrail_algorithm {
  FIRETRAIL_ALGORITHM_WHITE = -1, /* Static lookup table (fastest) */
  FIRETRAIL_ALGORITHM_ORANGE = 0, /* Adaptive lookup table (tier 0 / default) */
  FIRETRAIL_ALGORITHM_RED = 1, /* Frequency-tracked adaptive table (slower) */
} firetrail_algorithm;

typedef struct firetrail_encoder firetrail_encoder;
typedef struct firetrail_decoder firetrail_decoder;

/* --- Sizing & Training --- */

/* Worst-case compressed byte size for an input of `input_size` bytes. */
size_t firetrail_max_compressed_size(size_t input_size);

/* Byte size of a serialized lookup table (524288 bytes for default 64K x u64).
 */
size_t firetrail_table_size(void);

/* Train a lookup table from `sample` using the Red encoder.
 * Returns bytes written, or 0 on error. */
size_t firetrail_train_table(const uint8_t *sample, size_t sample_size,
                             uint8_t *output_table, size_t output_capacity);

/* --- Encoder --- */

firetrail_encoder *firetrail_encoder_create(firetrail_algorithm algorithm);
void firetrail_encoder_destroy(firetrail_encoder *encoder);
void firetrail_encoder_reset(firetrail_encoder *encoder);

bool firetrail_encoder_import_table(firetrail_encoder *encoder,
                                    const uint8_t *table, size_t table_size);
size_t firetrail_encoder_export_table(const firetrail_encoder *encoder,
                                      uint8_t *output_table,
                                      size_t output_capacity);

/* Compresses `input` into `output`. Returns compressed byte count, or 0 on
 * error. */
size_t firetrail_encoder_compress(firetrail_encoder *encoder,
                                  const uint8_t *input, size_t input_size,
                                  uint8_t *output, size_t output_capacity);

/* --- Decoder --- */

firetrail_decoder *firetrail_decoder_create(firetrail_algorithm algorithm);
void firetrail_decoder_destroy(firetrail_decoder *decoder);
void firetrail_decoder_reset(firetrail_decoder *decoder);

bool firetrail_decoder_import_table(firetrail_decoder *decoder,
                                    const uint8_t *table, size_t table_size);
size_t firetrail_decoder_export_table(const firetrail_decoder *decoder,
                                      uint8_t *output_table,
                                      size_t output_capacity);

/* Decompresses `input` into `output` of known `output_size`.
 * Returns `output_size`, or 0 on error. */
size_t firetrail_decoder_decompress(firetrail_decoder *decoder,
                                    const uint8_t *input, size_t input_size,
                                    uint8_t *output, size_t output_size);

#ifdef __cplusplus
}
#endif

#endif /* FIRETRAIL_H */
