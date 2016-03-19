for i in $(cat pending.txt); do
  git checkout $i && git rebase upstream/master && git push -f kentnl $i
done
