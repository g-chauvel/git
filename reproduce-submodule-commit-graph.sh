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

out=$(mktemp -d "/tmp/git-submodule-commit-graph.XXXXXX")

commits () {
	local repo=$1 label=$2 count=$3 i
	for ((i=1; i<=count; i++)); do
		printf '%s %s\n' "$label" "$i" >"$repo/$label.txt"
		git -C "$repo" add "$label.txt"
		git -C "$repo" commit -qm "$label $i"
	done
}

run_case () {
	local name=$1 initial_super_commits=$2 dir="$out/$1" super="$out/$1/super" sub="$out/$1/super/sub"
	local base ours theirs count_child count_super status=0 actual="" control=0 repo

	mkdir -p "$dir"
	git init -q -b main "$super"
	commits "$super" super "$initial_super_commits"
	git init -q -b main "$sub"
	commits "$sub" child 30

	base=$(git -C "$sub" rev-parse HEAD~20)
	ours=$(git -C "$sub" rev-parse HEAD~10)
	theirs=$(git -C "$sub" rev-parse HEAD)

	git -C "$sub" checkout -q --detach "$base"
	git -C "$super" add sub 2>"$dir/add-sub.log"
	git -C "$super" commit -qm base

	git -C "$super" branch theirs
	git -C "$super" checkout -qb ours
	git -C "$sub" checkout -q --detach "$ours"
	git -C "$super" add sub
	git -C "$super" commit -qm ours

	git -C "$super" checkout -q theirs
	git -C "$sub" checkout -q --detach "$theirs"
	git -C "$super" add sub
	git -C "$super" commit -qm theirs

	git -C "$super" checkout -q ours
	git -C "$sub" checkout -q --detach "$ours"

	for repo in "$super" "$sub"; do
		git -C "$repo" config core.commitGraph true
		git -C "$repo" commit-graph write --reachable
		git -C "$repo" commit-graph verify
	done

	count_child=$(git -C "$sub" rev-list --count --all)
	count_super=$(git -C "$super" rev-list --count --all)

	printf '\n%s: child=%s super=%s commits\n' "$name" "$count_child" "$count_super"
	git -C "$super" -c advice.submoduleMergeConflict=false merge --no-ff theirs -m merge >"$dir/merge.log" 2>&1 || status=$?
	if test "$status" -eq 0; then
		actual=$(git -C "$super" rev-parse HEAD:sub)
		if test "$actual" = "$theirs"; then
			printf '  PASS\n'
			return 0
		fi
	fi
	printf '  INCORRECT MERGE: exit=%s, expected=%s, actual=%s\n' \
		"$status" "$theirs" "${actual:-unavailable}"
	cat "$dir/merge.log"

	git -C "$super" reset --hard -q ours
	git -C "$super" -c core.commitGraph=false merge --no-ff theirs -m control >"$dir/control.log" 2>&1 || control=$?
	if test "$control" -ne 0 || test "$(git -C "$super" rev-parse HEAD:sub)" != "$theirs"; then
		exit 1
	fi
	printf '  merge PASSES with core.commitGraph=false\n\n'
}

run_case out-of-range 0
run_case in-range 40
