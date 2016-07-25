#!/bin/bash
cred=$'\e[31m'
cgreen=$'\e[32m'
cyellow=$'\e[33m'
creset=$'\e[0m'

GETOPT_ARGS=$(getopt -n "$0" -o '' -s bash --long do,branch: -- "$@")
DO=0

if [ $? != 0 ]; then
  echo "${cred} Exiting: Args invalid${creset}"
  exit 1
fi
eval set -- "$GETOPT_ARGS"
while true; do
  case "$1" in
    "--do") 
        DO=1 
        shift
        ;;
    "--")
        shift
        break
        ;;
    *) 
      echo "${cred} Arg parsing error${creset}";
      exit 1;
      ;;
  esac
done

BRANCH="$1"
TARGET_REMOTE="upstream"
TARGET_BRANCH="master"

upstream_sha() {
  git rev-parse "${TARGET_REMOTE}/${TARGET_BRANCH}";
}
terselog() {
  PAGER=cat git log --stat --oneline --reverse "$1".."$2" || exit 1;
}
do_send() {
  if [ $DO == 1 ]; then
    git push --signed=yes           "${TARGET_REMOTE}" "${BRANCH}:${TARGET_BRANCH}" || exit 1;
  else
    git push --signed=yes --dry-run "${TARGET_REMOTE}" "${BRANCH}:${TARGET_BRANCH}" || exit 1;
  fi
}

if [[ -z "$BRANCH" ]]; then
  echo "${cred}No branch specified${creset}";
  exit 1;
else
  echo "${cgreen}Prepping to push ${cyellow}${BRANCH}${cgreen} to ${TARGET_REMOTE}/${TARGET_BRANCH}${creset}";
fi

git checkout ${BRANCH} || exit 1;

CURRENT_CREF="$(upstream_sha)"

if [ $DO == 1 ]; then
  echo "${cred}Doing Push${creset}"
  do_send || exit 1;
  echo "${cgreen}Pushed!${creset}"
else
  echo "${cgreen}Staging mode${creset}"
  git remote update -p ${TARGET_REMOTE} || exit 1;
  NEW_CREF="$(git rev-parse "${TARGET_REMOTE}/${TARGET_BRANCH}" )"
  if [ "${CURRENT_CREF}" != "${NEW_CREF}" ]; then
    echo "${cyellow}New Commits... ${creset}"
    echo "${cyellow}===${creset}"
    terselog "${CURRENT_CREF}" "${NEW_CREF}";
    echo "${cyellow}===${creset}"

  fi
  git rebase "${TARGET_REMOTE}/${TARGET_BRANCH}"            || exit 1;
  echo "${cyellow}===${creset}"
  terselog "${TARGET_REMOTE}/${TARGET_BRANCH}" "${BRANCH}"  || exit 1;
  echo "${cyellow}===${creset}"
  do_send                                                   || exit 1;
  echo "${cgreen}Clean!${creset}"
fi
