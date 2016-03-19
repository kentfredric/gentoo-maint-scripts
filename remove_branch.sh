if [ -z "$1" ]; then
  echo "Need a branch name";
  exit 1;
fi

echo "Checking $1";

if git branch -a --contains $1 | grep -q remotes/upstream/master; then
  echo "* $1 in upstream... purging"

  if git branch -a --points-at HEAD | grep -E -q "^\s*\*\s*$1\s*$"; then
    echo "* Already on $1, can't remove";
    exit 1;
  fi

  git push kentnl :$1
  git branch -d $1
else
  echo "* $1 not yet merged";
fi
