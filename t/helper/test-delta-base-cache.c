#define USE_THE_REPOSITORY_VARIABLE

#include "test-tool.h"
#include "hex.h"
#include "packfile.h"
#include "setup.h"

int cmd__delta_base_cache(int argc, const char **argv)
{
	struct packed_git *pack;
	struct object_id oid, base_oid;
	off_t offset, base_offset;
	void *data;

	if (argc != 4)
		usage("test-tool delta-base-cache <pack.idx> <delta> <base>");

	setup_git_directory(the_repository);

	if (get_oid_hex(argv[2], &oid) || get_oid_hex(argv[3], &base_oid))
		die("invalid object ID");

	pack = add_packed_git(the_repository, argv[1], strlen(argv[1]), 1);
	if (!pack)
		die("cannot open pack");

	offset = find_pack_entry_one(&oid, pack);
	base_offset = find_pack_entry_one(&base_oid, pack);
	if (!offset || !base_offset)
		die("object is missing from pack");

	data = unpack_entry(the_repository, pack, offset, NULL, NULL);
	if (!data)
		die("cannot unpack object");
	free(data);

	if (!in_delta_base_cache(pack, base_offset))
		die("delta base was not cached");

	close_pack(pack);

	if (in_delta_base_cache(pack, base_offset))
		die("delta base remains cached after closing pack");

	free(pack);
	return 0;
}
