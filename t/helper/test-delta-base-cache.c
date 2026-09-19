#define USE_THE_REPOSITORY_VARIABLE

#include "test-tool.h"
#include "hex.h"
#include "object-file.h"
#include "packfile.h"
#include "setup.h"

static off_t delta_base_offset(struct packed_git *pack,
			       const struct object_id *oid)
{
	struct pack_window *window = NULL;
	off_t offset, pos, base;
	size_t size;
	int type;

	offset = find_pack_entry_one(oid, pack);
	if (!offset)
		die("object is missing from pack: %s", oid_to_hex(oid));
	pos = offset;
	type = unpack_object_header(pack, &window, &pos, &size);
	if (type != OBJ_OFS_DELTA && type != OBJ_REF_DELTA)
		die("object is not stored as a delta: %s", oid_to_hex(oid));
	base = get_delta_base(pack, &window, &pos, type, offset);
	unuse_pack(&window);
	if (!base)
		die("cannot locate delta base for %s", oid_to_hex(oid));
	return base;
}

int cmd__delta_base_cache(int argc, const char **argv)
{
	struct packed_git *first, *second;
	struct object_id first_oid, second_oid, actual_oid;
	enum object_type type;
	size_t size;
	void *data;

	if (argc != 5)
		die("usage: test-tool delta-base-cache <pack-A.idx> <object-A> "
		    "<pack-B.idx> <object-B>");
	setup_git_directory(the_repository);
	if (get_oid_hex(argv[2], &first_oid) || get_oid_hex(argv[4], &second_oid))
		die("invalid object ID");
	if (strlen(argv[1]) != strlen(argv[3]))
		die("pack index paths must have the same length");
	first = add_packed_git(the_repository, argv[1], strlen(argv[1]), 1);
	second = add_packed_git(the_repository, argv[3], strlen(argv[3]), 1);
	if (!first || !second || open_pack_index(first) || open_pack_index(second))
		die("cannot open pack indexes");
	if (delta_base_offset(first, &first_oid) !=
	    delta_base_offset(second, &second_oid))
		die("delta bases have different pack offsets");

	data = unpack_entry(the_repository, first,
			    find_pack_entry_one(&first_oid, first), NULL, NULL);
	if (!data)
		die("cannot unpack first object");
	free(data);
	close_pack(first);

	/*
	 * Simulate the allocator reusing the same address for a new pack.
	 * Reinitialize first in place as alloc_packed_git() would, then
	 * retarget it at the second pack, whose path has the same length.
	 */
	memset(first, 0, sizeof(*first));
	first->pack_fd = -1;
	first->repo = the_repository;
	INIT_LIST_HEAD(&first->delta_base_cache);
	memcpy(first->pack_name, second->pack_name,
	       strlen(second->pack_name) + 1);
	first->pack_size = second->pack_size;
	close_pack(second);
	free(second);

	if (open_pack_index(first))
		die("cannot reopen second pack index");
	data = unpack_entry(the_repository, first,
			    find_pack_entry_one(&second_oid, first), &type, &size);
	if (!data)
		die("cannot unpack second object");
	hash_object_file(the_repository->hash_algo, data, size, type, &actual_oid);
	free(data);
	close_pack(first);
	free(first);
	if (!oideq(&actual_oid, &second_oid))
		return error("second object differs after pack reuse");
	return 0;
}
