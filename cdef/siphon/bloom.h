typedef struct {
	double fpp;
	uint64_t count;
	uint64_t bits;
	uint32_t seed;
	uint8_t hashes;
	uint8_t bytes[3];
} SpBloom;

SpBloom *sp_bloom_create (size_t hint, double fpp, uint32_t seed);
void sp_bloom_destroy (SpBloom *self);
bool sp_bloom_is_capable (SpBloom *self, size_t hint, double fpp);
bool sp_bloom_can_hold (SpBloom *self, size_t more);
uint64_t sp_bloom_hash (SpBloom *self, const void *restrict buf, size_t len);
bool sp_bloom_maybe (SpBloom *self, const void *restrict buf, size_t len);
bool sp_bloom_maybe_hash (SpBloom *self, uint64_t hash);
void sp_bloom_put (SpBloom *self, const void *restrict buf, size_t len);
void sp_bloom_put_hash (SpBloom *self, uint64_t hash);
void sp_bloom_clear (SpBloom *self);
SpBloom *sp_bloom_copy (SpBloom *self);
