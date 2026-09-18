#!/usr/bin/env bash

# Reproduce a stale delta-base-cache entry across two submodule repositories.
# Exit 0 when a merge of A tries to read a commit that belongs only to B.
# The address reuse depends on malloc and may not happen on every system.
set -euo pipefail

tmpdir=$(mktemp -d)

for name in A B; do
	mkdir "$tmpdir/source-$name"
	cd "$tmpdir/source-$name"
	git init -q -b main
	git config user.name Repro
	git config user.email repro@example.invalid
	printf '%s base\n' "$name" >file
	git add file
	git commit -qm "$name base"
	git switch -qc branch-a
	git commit --allow-empty -qm "$name branch-a"
	git switch -qc branch-b main
	git commit --allow-empty -qm "$name branch-b"
	git switch -q main
done

mkdir "$tmpdir/super"
cd "$tmpdir/super"
git init -q -b base
git config user.name Repro
git config user.email repro@example.invalid
for name in A B; do
	git -c protocol.file.allow=always submodule add -q \
		"file://$tmpdir/source-$name" "$name"
done
git add .
git commit -qm base

git switch -qc branch-a
for name in A B; do
	(cd "$name" && git switch -q -c branch-a --track origin/branch-a)
done
git add A B
git commit -qm branch-a

git switch -qc branch-b base
for name in A B; do
	(cd "$name" && git switch -q -c branch-b --track origin/branch-b)
done
git add A B
git commit -qm branch-b

cd "$tmpdir"
git -c protocol.file.allow=always clone -q --no-local "file://$tmpdir/super" clone
cd clone
git config user.name Repro
git config user.email repro@example.invalid
git -c protocol.file.allow=always submodule update --init -q
git switch -q -c branch-a --track origin/branch-a
if merge_output=$(git merge branch-b 2>&1); then
	merge_status=0
else
	merge_status=$?
fi
printf 'git merge exit status: %s\n%s\n' "$merge_status" "$merge_output"

if [[ $merge_output =~ Could\ not\ read\ ([0-9a-f]{40}|[0-9a-f]{64}) ]]; then
	foreign_oid=${BASH_REMATCH[1]}
	if ! (cd A && git cat-file -e "$foreign_oid^{commit}" 2>/dev/null) &&
	(cd B && git cat-file -e "$foreign_oid^{commit}" 2>/dev/null); then
		printf 'REPRODUCED: OID %s belongs to B, but Git read it in A\n' \
			"$foreign_oid"
		exit 0
	fi
fi

echo 'NOT REPRODUCED: no foreign B OID was read from A'
exit 1
