#!/bin/sh

test_description='delta base cache lifetime across pack closure'

. ./test-lib.sh

# The delta base cache is keyed by (packed_git pointer, base offset).
# Reading B from A-B.pack caches A.
# The helper then closes that pack and, since B has the same offset
# as A, reuses its packed_git structure for B-C.pack to reproduce
# the same cache key. If closing the pack leaves A in the cache,
# reading C would use A instead of B as its delta base. The delta
# is chosen so that using A produces incorrect contents for C,
# which the helper detects by checking the resulting object ID.
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
