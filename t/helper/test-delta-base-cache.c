#define USE_THE_REPOSITORY_VARIABLE

#include "test-tool.h"
#include "hex.h"
#include "object-file.h"
#include "packfile.h"
#include "setup.h"

static off_t delta_base_offset(struct packed_git *pack,
			       const struct object_id *oid, off_t *object_offset)
{
	struct pack_window *window = NULL;
	off_t pos, base;
	size_t size;
	int type;

	*object_offset = find_pack_entry_one(oid, pack);
	if (!*object_offset)
		die("object is missing from pack: %s", oid_to_hex(oid));
	pos = *object_offset;
	type = unpack_object_header(pack, &window, &pos, &size);
	if (type != OBJ_OFS_DELTA && type != OBJ_REF_DELTA)
		die("object is not stored as a delta: %s", oid_to_hex(oid));
	base = get_delta_base(pack, &window, &pos, type, *object_offset);
	unuse_pack(&window);
	if (!base)
		die("cannot locate delta base for %s", oid_to_hex(oid));
	return base;
}

static void reuse_pack_storage(struct packed_git *closed,
			       struct packed_git *replacement)
{
	size_t name_len = strlen(replacement->pack_name) + 1;

	if (strlen(closed->pack_name) + 1 != name_len)
		die("pack paths must have the same length");

	/* Keep the old address while transferring ownership of the new pack. */
	*closed = *replacement;
	memcpy(closed->pack_name, replacement->pack_name, name_len);
	free(replacement);
}

int cmd__delta_base_cache(int argc, const char **argv)
{
	struct packed_git *first, *second;
	struct object_id first_oid, second_oid, actual_oid;
	enum object_type type;
	size_t size;
	void *data;
	off_t first_base, second_base, first_offset, second_offset;
	int result;

	if (argc != 5)
		die("usage: test-tool delta-base-cache <pack-A.idx> <object-A> <pack-B.idx> <object-B>");
	setup_git_directory(the_repository);
	if (get_oid_hex(argv[2], &first_oid) || get_oid_hex(argv[4], &second_oid))
		die("invalid object ID");
	first = add_packed_git(the_repository, argv[1], strlen(argv[1]), 1);
	second = add_packed_git(the_repository, argv[3], strlen(argv[3]), 1);
	if (!first || !second || open_pack_index(first) || open_pack_index(second))
		die("cannot open pack indexes");
	first_base = delta_base_offset(first, &first_oid, &first_offset);
	second_base = delta_base_offset(second, &second_oid, &second_offset);
	if (first_base != second_base)
		die("delta bases have different pack offsets");

	/* Populate the cache from the first pack. */
	data = unpack_entry(the_repository, first, first_offset, NULL, NULL);
	if (!data)
		die("cannot unpack first object");
	free(data);
	close_pack(first);

	/* Read the second pack through the same cache key address. */
	reuse_pack_storage(first, second);
	data = unpack_entry(the_repository, first, second_offset, &type, &size);
	if (!data)
		die("cannot unpack second object");
	hash_object_file(the_repository->hash_algo, data, size, type, &actual_oid);
	result = !oideq(&actual_oid, &second_oid);
	free(data);
	close_pack(first);
	free(first);
	clear_delta_base_cache();
	if (result)
		error("second object differs after pack reuse");
	return result;
}
