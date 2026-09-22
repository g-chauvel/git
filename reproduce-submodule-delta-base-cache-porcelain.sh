#!/usr/bin/env bash

set -euo pipefail

unset $(git rev-parse --local-env-vars)
export LC_ALL=C
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_DEFAULT_HASH=sha1
export GIT_TEMPLATE_DIR=
export GIT_AUTHOR_NAME=Reproducer
export GIT_AUTHOR_EMAIL=reproducer@example.invalid
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
export GIT_AUTHOR_DATE='2000-01-01T00:00:00 +0000'
export GIT_COMMITTER_DATE='2000-01-01T00:00:00 +0000'

tmpdir=$(mktemp -d)

for name in A B; do
	mkdir "$tmpdir/source-$name"
	cd "$tmpdir/source-$name"
	git init -q -b main
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
git config --local protocol.file.allow always
for name in A B; do
	# reproduces the bug
	git -c protocol.file.allow=always submodule add -q "file://$tmpdir/source-$name" "$name"

	# does not reproduce the bug
	# git  -c protocol.file.allow=always submodule add -q "$tmpdir/source-$name" "$name"
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
	if ! (cd A && git cat-file -e "$foreign_oid" 2>/dev/null) &&
	(cd B && git cat-file -e "$foreign_oid" 2>/dev/null); then
		printf 'BUG: OID %s belongs to B instead of A\n' "$foreign_oid"
	fi
fi