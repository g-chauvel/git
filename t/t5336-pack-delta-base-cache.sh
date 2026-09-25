#!/bin/sh

test_description='delta base cache lifetime across pack closure'

. ./test-lib.sh
. "$TEST_DIRECTORY"/lib-pack.sh

test_expect_success 'delta base cache entries do not outlive their pack' '
	cache_A=$(test_oid packlib_7_0) &&
	cache_B=$(test_oid packlib_7_76) &&
	{
		pack_header 2 &&
		pack_obj "$cache_A" &&
		pack_obj "$cache_B" "$cache_A"
	} >cache.pack &&
	pack_trailer cache.pack &&
	git index-pack -o cache.idx cache.pack &&
	test-tool delta-base-cache cache.idx "$cache_B"
'

test_done
