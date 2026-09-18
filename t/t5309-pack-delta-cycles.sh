#!/bin/sh

test_description='test index-pack handling of delta cycles in packfiles'

. ./test-lib.sh
. "$TEST_DIRECTORY"/lib-pack.sh

# Two similar-ish objects that we have computed deltas between.
A=$(test_oid packlib_7_0)
B=$(test_oid packlib_7_76)

# double-check our hand-constucted packs
test_expect_success 'index-pack works with a single delta (A->B)' '
	clear_packs &&
	{
		pack_header 2 &&
		pack_obj $A $B &&
		pack_obj $B
	} >ab.pack &&
	pack_trailer ab.pack &&
	git index-pack --stdin <ab.pack &&
	git cat-file -t $A &&
	git cat-file -t $B
'

test_expect_success 'index-pack works with a single delta (B->A)' '
	clear_packs &&
	{
		pack_header 2 &&
		pack_obj $A &&
		pack_obj $B $A
	} >ba.pack &&
	pack_trailer ba.pack &&
	git index-pack --stdin <ba.pack &&
	git cat-file -t $A &&
	git cat-file -t $B
'

test_expect_success 'index-pack detects missing base objects' '
	clear_packs &&
	{
		pack_header 1 &&
		pack_obj $A $B
	} >missing.pack &&
	pack_trailer missing.pack &&
	test_must_fail git index-pack --fix-thin --stdin <missing.pack
'

test_expect_success 'index-pack detects REF_DELTA cycles' '
	clear_packs &&
	{
		pack_header 2 &&
		pack_obj $A $B &&
		pack_obj $B $A
	} >cycle.pack &&
	pack_trailer cycle.pack &&
	test_must_fail git index-pack --fix-thin --stdin <cycle.pack
'

test_expect_success 'failover to an object in another pack' '
	clear_packs &&
	git index-pack --stdin <ab.pack &&

	# This cycle does not fail since the existence of A & B in
	# the repo allows us to resolve the cycle.
	git index-pack --stdin --fix-thin <cycle.pack
'

test_expect_success 'failover to a duplicate object in the same pack' '
	clear_packs &&
	{
		pack_header 3 &&
		pack_obj $A $B &&
		pack_obj $B $A &&
		pack_obj $A
	} >recoverable.pack &&
	pack_trailer recoverable.pack &&

	# This cycle does not fail since the existence of a full copy
	# of A in the pack allows us to resolve the cycle.
	git index-pack --fix-thin --stdin <recoverable.pack
'

test_expect_success 'index-pack works with thin pack A->B->C with B on disk' '
	git init server &&
	(
		cd server &&
		test_commit_bulk 4
	) &&

	A=$(git -C server rev-parse HEAD^{tree}) &&
	B=$(git -C server rev-parse HEAD~1^{tree}) &&
	C=$(git -C server rev-parse HEAD~2^{tree}) &&
	git -C server reset --hard HEAD~1 &&

	test-tool -C server pack-deltas --num-objects=2 >thin.pack <<-EOF &&
	REF_DELTA $A $B
	REF_DELTA $B $C
	EOF

	git clone "file://$(pwd)/server" client &&
	(
		cd client &&
		git index-pack --fix-thin --stdin <../thin.pack
	)
'

test_expect_success 'delta base cache entries do not outlive their pack' '
	A=$(test_oid packlib_7_0) &&
	B=$(test_oid packlib_7_76) &&
	C=$(test_oid packlib_0_76) &&
	clear_packs &&
	{
		pack_header 2 &&
		pack_obj $A &&
		pack_obj $B $A
	} >A-B.pack &&
	pack_trailer A-B.pack &&
	{
		pack_header 2 &&
		pack_obj $B &&
		# Store C as an OFS_DELTA from B. Write it manually because
		# pack-objects may choose a literal-only delta, which would let this
		# regression test pass with a stale delta-base cache.
		#
		# B is 07 3e and C is 00 3e. The inflated delta is:
		#   \002\002          base and result sizes
		#   \001\000          insert C[0]
		#   \221\001\001      copy one byte at B offset 1
		# A stale A base (07 00) would therefore reconstruct 00 00, not C.
		#
		# \147 is an OFS_DELTA header for 7 delta bytes; \013 points
		# 11 bytes back to B. The remaining bytes are its zlib stream.
		printf "\147\013\170\001\143\142\142\144\230\310\310\010\000\001\334\000\231"
	} >B-C.pack &&
	pack_trailer B-C.pack &&
	git index-pack -o A-B.idx A-B.pack &&
	git index-pack -o B-C.idx B-C.pack &&
	test-tool delta-base-cache \
		A-B.idx $B \
		B-C.idx $C
'

test_done
