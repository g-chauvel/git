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

# The delta base cache is process-wide. Closing a pack must evict its entries
# before the same packed_git address is used for another pack.
test_expect_success 'delta base cache entries do not outlive their pack' '
	mkdir cache-lifetime &&
	(
		cd cache-lifetime &&
		create_source () {
			name=$1 &&
			git init -q "source-$name" &&
			printf "%s base\n" "$name" >"source-$name/file" &&
			git -C "source-$name" add file &&
			git -C "source-$name" commit -qm "$name base" &&
			git -C "source-$name" rev-parse HEAD >"$name.base" &&
			tree=$(git -C "source-$name" rev-parse "HEAD^{tree}") &&
			printf "%s release\n" "$name" |
			git -C "source-$name" commit-tree "$tree" -p "$(cat "$name.base")" >"$name.release" &&
			printf "%s toto\n" "$name" |
			git -C "source-$name" commit-tree "$tree" -p "$(cat "$name.base")" >"$name.toto" &&
			git -C "source-$name" update-ref refs/heads/release-tip "$(cat "$name.release")" &&
			git -C "source-$name" update-ref refs/heads/toto-tip "$(cat "$name.toto")"
		} &&
		create_source E &&
		create_source F &&
		git clone -q --no-local "file://$PWD/source-E" clone-E &&
		git clone -q --no-local "file://$PWD/source-F" clone-F &&
		test-tool delta-base-cache \
			"$PWD"/clone-E/.git/objects/pack/*.idx "$(cat E.toto)" \
			"$PWD"/clone-F/.git/objects/pack/*.idx "$(cat F.toto)"
	)
'

test_done
