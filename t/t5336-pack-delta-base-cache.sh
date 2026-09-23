#!/bin/sh

test_description='delta base cache lifetime across pack closure'

. ./test-lib.sh

# The delta base cache is keyed by (packed_git pointer, base offset), not
# by the base object's OID. Closing a pack must discard its cache entries
# before that pointer can be reused for another pack.
#
# Use three same-sized blobs, A = a0 + common, B = b1 + common, and
# C = c1 + common. All three share the same suffix. B and C also share
# the second byte, which differs in A; copying that byte from a stale A
# would therefore change the result. B is both the delta target in
# A-B.pack and the full base in B-C.pack; C gives us a second delta to
# read after reusing the first pack's pointer.
# A and B have the same size so applying the B-to-C delta to A does not
# fail merely because the base size differs from the delta's expectation.
#
# Check that applying the B-to-C delta to A does not produce C.
# Different bases alone do not guarantee different results: a delta could
# insert all differing bytes as literals and copy only their common suffix.
# This check ensures that using A instead of B changes the result, so the
# final OID check cannot hide a stale base.
# The pack helper regenerates the same delta from B and C; b-c.delta is
# only used for this check, not as input to pack construction.
#
# Put each full base first in its pack, at offset 12, so A and B have the
# same base offset regardless of their compressed sizes. Each pack needs
# its own index to locate the requested object and resolve its REF_DELTA
# base's OID to that offset. B has the same OID in both packs despite its
# different storage representations.
#
# Before close_pack(first), the C helper unpacks B from A-B.pack, caching
# A under (first, 12). Freeing the returned B does not free the cached A.
#
# The helper then uses memset() and field initialization to reset first
# in place and retarget it to B-C.pack. This simulates allocation at the
# same address deterministically, without relying on free()/malloc().
# Resetting the packed_git structure does not clear the global cache:
# close_pack() must already have removed its entries.
#
# Reading C through the reused pointer must now use B, not a stale A at
# the same (first, 12) key. The helper hashes the reconstructed object's
# type, size, and contents and expects C's OID. If A survived closure,
# the wrong-base check above ensures a different result and hence a
# different OID, causing the helper to fail even with correct pack indexes.
test_expect_success 'delta base cache entries do not outlive their pack' '
	test-tool genrandom cache-data 1024 >common &&
	{ printf "a0" && cat common; } >a &&
	{ printf "b1" && cat common; } >b &&
	{ printf "c1" && cat common; } >c &&
	A=$(git hash-object -w a) &&
	B=$(git hash-object -w b) &&
	C=$(git hash-object -w c) &&

	test-tool delta -d b c b-c.delta &&
	test-tool delta -p a b-c.delta stale &&
	! cmp -s c stale &&

	test-tool pack-deltas --num-objects=2 >A-B.pack <<-EOF &&
	FULL $A
	REF_DELTA $B $A
	EOF
	test-tool pack-deltas --num-objects=2 >B-C.pack <<-EOF &&
	FULL $B
	REF_DELTA $C $B
	EOF

	git index-pack -o A-B.idx A-B.pack &&
	git index-pack -o B-C.idx B-C.pack &&

	test-tool delta-base-cache \
		A-B.idx $B \
		B-C.idx $C
'

test_done
