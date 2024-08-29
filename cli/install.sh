#!/usr/bin/env bash

set -euo pipefail

# check that 'bun' is installed

if ! command -v bun > /dev/null; then
  echo "bun is not installed. Follow the instructions at https://bun.sh/docs/installation"
  exit 1
fi

REPO="https://github.com/wormhole-foundation/example-native-token-transfers.git"

function main {
  branch=""

  while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
      -b|--branch)
        branch="$2"
        shift
        shift
        ;;
      *)
        echo "Unknown option $key"
        exit 1
        ;;
    esac
  done

  path=""

  # check if there's a package.json in the parent directory, with "name": "@wormhole-foundation/ntt-cli"
  if [ -f "$(dirname $0)/package.json" ] && grep -q '"name": "@wormhole-foundation/ntt-cli"' "$(dirname $0)/package.json"; then
  path="$(dirname $0)/.."
  else
    # if branch is set, use it. otherwise use the latest tag of the form "vX.Y.Z+cli" or the 'cli' branch
    if [ -z "$branch" ]; then
      branch="$(select_branch)"
    fi

    # clone to $HOME/.ntt-cli if it doesn't exist, otherwise update it
    echo "Cloning $REPO $branch"

    mkdir -p "$HOME/.ntt-cli"
    path="$HOME/.ntt-cli/.checkout"

    if [ ! -d "$path" ]; then
      git clone --branch "$branch" "$REPO" "$path"
    else
      pushd "$path"
      # update origin url to REPO
      git remote set-url origin "$REPO"
      git fetch origin
      # reset hard
      git reset --hard "origin/$branch"
      popd
    fi

  fi

  install_cli "$path"
}

# function that determines which branch/tag to clone
function select_branch {
  # if the repo has a tag of the form "vX.Y.Z+cli", use that (the latest one)
  # otherwise we'll use the 'cli' branch
  branch=""
  regex="refs/tags/v[0-9]*\.[0-9]*\.[0-9]*+cli"
  if git ls-remote --tags "$REPO" | grep -q "$regex"; then
    branch="$(git ls-remote --tags "$REPO" | grep "$regex" | sort -V | tail -n 1 | awk '{print $2}')"
  else
    branch="cli"
  fi

  echo "$branch"
}

function install_cli {
  cd "$1"

  # if 'ntt' is already installed, uninstall it
  # just check with 'which'
  if which ntt > /dev/null; then
    echo "Removing existing ntt CLI"
    rm $(which ntt)
  fi

  # swallow the output of the first install
  # TODO: figure out why it fails the first time.
  bun install > /dev/null 2>&1 || true
  bun install

  # make a temporary directory

  tmpdir="$(mktemp -d)"

  # create a temporary symlink 'npm' to 'bun'

  ln -s "$(command -v bun)" "$tmpdir/npm"

  # add the temporary directory to the PATH

  export PATH="$tmpdir:$PATH"

  # swallow the output of the first build
  # TODO: figure out why it fails the first time.
  bun --bun run --filter '*' build > /dev/null 2>&1 || true
  bun --bun run --filter '*' build

  # remove the temporary directory

  rm -r "$tmpdir"

  # now link the CLI

  cd cli

  bun link

  bun link @wormhole-foundation/ntt-cli
}

main "$@"
