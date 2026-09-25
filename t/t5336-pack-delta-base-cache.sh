#!/bin/sh

test_description='delta base cache lifetime across pack closure'

. ./test-lib.sh
. "$TEST_DIRECTORY"/lib-pack.sh

test_expect_success 'delta base cache entries do not outlive their pack' '
	base=$(test_oid packlib_7_0) &&
	delta=$(test_oid packlib_7_76) &&
	{
		pack_header 2 &&
		pack_obj "$base" &&
		pack_obj "$delta" "$base"
	} >cache.pack &&
	pack_trailer cache.pack &&
	git index-pack -o cache.idx cache.pack &&
	test-tool delta-base-cache cache.idx "$delta" "$base"
'

test_done
