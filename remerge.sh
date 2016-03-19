die() {
  echo "SHIT $@";
  exit 1;
}
git checkout upstream/master || die
git branch -D noodleunion;
git checkout -b noodleunion upstream/master && \
  git merge $( cat ./pending.txt )
