#define USE_THE_REPOSITORY_VARIABLE

#include "test-tool.h"
#include "hex.h"
#include "packfile.h"
#include "setup.h"

int cmd__delta_base_cache(int argc, const char **argv)
{
	struct packed_git *pack;
	struct pack_window *window = NULL;
	struct object_id oid;
	uintptr_t pack_address;
	off_t offset, pos, base_offset;
	size_t size;
	int type;
	void *data;

	if (argc != 3)
		die("usage: test-tool delta-base-cache <pack.idx> <object>");
	setup_git_directory(the_repository);
	if (get_oid_hex(argv[2], &oid))
		die("invalid object ID");
	pack = add_packed_git(the_repository, argv[1], strlen(argv[1]), 1);
	if (!pack)
		die("cannot open pack");

	offset = find_pack_entry_one(&oid, pack);
	if (!offset)
		die("object is missing from pack: %s", oid_to_hex(&oid));
	pos = offset;
	type = unpack_object_header(pack, &window, &pos, &size);
	if (type != OBJ_OFS_DELTA && type != OBJ_REF_DELTA)
		die("object is not stored as a delta: %s", oid_to_hex(&oid));
	base_offset = get_delta_base(pack, &window, &pos, type, offset);
	unuse_pack(&window);
	if (!base_offset)
		die("cannot locate delta base for %s", oid_to_hex(&oid));

	data = unpack_entry(the_repository, pack, offset, NULL, NULL);
	if (!data)
		die("cannot unpack object");
	free(data);
	if (!delta_base_cache_has_address((uintptr_t)pack, base_offset))
		die("delta base was not cached");

	pack_address = (uintptr_t)pack;
	close_pack(pack);
	free(pack);
	if (delta_base_cache_has_address(pack_address, base_offset))
		return error("delta base cache retains a freed pack address");
	return 0;
}
