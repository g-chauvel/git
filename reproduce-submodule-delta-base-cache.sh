#!/usr/bin/env bash

# Reproduce a stale delta-base-cache entry across two submodule repositories.
# Exit 0 when a merge of A tries to read a commit that belongs only to B.
# The address reuse depends on malloc and may not happen on every system.
set -euo pipefail

tmpdir=$(mktemp -d)
echo "Reproduction directory: $tmpdir"

declare -A base branch_a branch_b
for name in A B; do
    mkdir "$tmpdir/source-$name"
    cd "$tmpdir/source-$name"
    git init -q -b main
    git config user.name Repro
    git config user.email repro@example.invalid
    printf '%s base\n' "$name" >file
    git add file
    git commit -qm "$name base"
    base[$name]=$(git rev-parse HEAD)
    tree=$(git rev-parse 'HEAD^{tree}')
    branch_a[$name]=$(printf '%s branch-a\n' "$name" |
    git commit-tree "$tree" -p "${base[$name]}")
    branch_b[$name]=$(printf '%s branch-b\n' "$name" |
    git commit-tree "$tree" -p "${base[$name]}")
    git update-ref refs/heads/branch-a-tip "${branch_a[$name]}"
    git update-ref refs/heads/branch-b-tip "${branch_b[$name]}"
done

mkdir "$tmpdir/super"
cd "$tmpdir/super"
git init -q -b base
git config user.name Repro
git config user.email repro@example.invalid
for name in A B; do
    git -c protocol.file.allow=always submodule add -q \
    "file://$tmpdir/source-$name" "$name"
    (cd "$name" && git checkout -q "${base[$name]}")
done
git add .
git commit -qm base
super_base=$(git rev-parse HEAD)

git switch -qc branch-a "$super_base"
for name in A B; do
    git update-index --add --cacheinfo "160000,${branch_a[$name]},$name"
done
git commit -qm branch-a
super_branch_a=$(git rev-parse HEAD)

git switch -qc branch-b "$super_base"
for name in A B; do
    git update-index --add --cacheinfo "160000,${branch_b[$name]},$name"
done
git commit -qm branch-b
super_branch_b=$(git rev-parse HEAD)

cd "$tmpdir"
git -c protocol.file.allow=always clone -q --no-local "file://$tmpdir/super" clone
cd clone
git config user.name Repro
git config user.email repro@example.invalid
git -c protocol.file.allow=always submodule update --init -q
git switch -qc branch-a "$super_branch_a"

if merge_output=$(git merge "$super_branch_b" 2>&1); then
    merge_status=0
else
    merge_status=$?
fi
printf 'git merge exit status: %s\n%s\n' "$merge_status" "$merge_output"

foreign_oid=
if [[ $merge_output =~ Could\ not\ read\ ([0-9a-f]{40}|[0-9a-f]{64}) ]]; then
    foreign_oid=${BASH_REMATCH[1]}
fi
if [[ -n $foreign_oid ]] &&
    ! (cd A && git cat-file -e "$foreign_oid^{commit}" 2>/dev/null) &&
    (cd B && git cat-file -e "$foreign_oid^{commit}" 2>/dev/null); then
    printf 'REPRODUCED: OID %s belongs to B, but Git read it in A\n' "$foreign_oid"
    exit 0
fi

echo 'NOT REPRODUCED: no foreign B OID was read from A'
exit 1
