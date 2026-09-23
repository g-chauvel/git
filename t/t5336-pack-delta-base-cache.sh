#!/bin/sh

test_description='delta base cache lifetime across pack closure'

. ./test-lib.sh

test_expect_success 'delta base cache entries do not outlive their pack' '
	# B and C have "1" as their second byte; A has "0" there.
	test-tool genrandom cache-data 1024 >common &&
	{ printf "a0" && cat common; } >a &&
	{ printf "b1" && cat common; } >b &&
	{ printf "c1" && cat common; } >c &&
	A=$(git hash-object -w a) &&
	B=$(git hash-object -w b) &&
	C=$(git hash-object -w c) &&

	# The delta from B to C must copy bytes where A differs from B.
	# Otherwise a stale base from the first pack could still produce C.
	test-tool delta -d b c b-c.delta &&
	test-tool delta -p a b-c.delta stale &&
	! cmp -s c stale &&

	# Each FULL base is the first entry in its pack, giving both bases
	# the same offset regardless of their compressed sizes.
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
