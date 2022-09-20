#!/bin/bash

set -e

if [[ -z "$GITHUB_TOKEN" ]]; then
	echo "Please set the GITHUB_TOKEN env variable."
	exit 1
fi

AUTH_HEADER="Authorization: token $GITHUB_TOKEN"
CAN_REBASE=""
pr_response=""
for ((i = 0 ; i < 3 ; i++)); do
	pr_response=$(curl -X GET -s -H "${AUTH_HEADER}" -H "Accept: application/vnd.github.v3+json" \
		"https://api.github.com/repos/$GITHUB_REPOSITORY/pulls/$INPUT_PR_NUMBER")
	CAN_REBASE=$(echo "$pr_response" | jq -r .rebaseable)
	if [[ "$CAN_REBASE" != "null" ]]; then
		break
	fi
	echo "PR cannot rebase, retry after 5 seconds"
	sleep 5
done

if [[ "$CAN_REBASE" != "true" ]] ; then
	echo "PR cannot rebase!"
fi

BASE_REPO=$(echo "$pr_response" | jq -r .base.repo.full_name)
BASE_BRANCH=$(echo "$pr_response" | jq -r .base.ref)
echo "$BASE_BRANCH is Base branch for PR #$INPUT_PR_NUMBER"
if [[ -z "$BASE_BRANCH" ]]; then
	echo "Cannot get base branch information for PR #$INPUT_PR_NUMBER!"
	exit 1
fi

USER_LOGIN=$(jq -r ".comment.user.login" "$GITHUB_EVENT_PATH")         
if [[ "$USER_LOGIN" == "null" ]]; then
	USER_LOGIN=$(jq -r ".pull_request.user.login" "$GITHUB_EVENT_PATH")
fi

USER_NAME="${USER_LOGIN} (Automatic Rebase PR Action)"
USER_EMAIL="$USER_LOGIN@users.noreply.github.com"
echo "Automatic Rebase using Git Username: $USER_NAME"
echo "Automatic Rebase using Git Email: $USER_EMAIL"

HEAD_REPO=$(echo "$pr_response" | jq -r .head.repo.full_name)
HEAD_BRANCH=$(echo "$pr_response" | jq -r .head.ref)

USER_TOKEN=${USER_LOGIN//-/_}_TOKEN
UNTRIMMED_COMMITTER_TOKEN=${!USER_TOKEN:-$GITHUB_TOKEN}
COMMITTER_TOKEN="$(echo -e "${UNTRIMMED_COMMITTER_TOKEN}" | tr -d '[:space:]')"

git config --global --add safe.directory /github/workspace
git remote set-url origin https://x-access-token:$COMMITTER_TOKEN@github.com/$GITHUB_REPOSITORY.git
git config --global user.email "$USER_EMAIL"
git config --global user.name "$USER_NAME"

git remote add fork https://x-access-token:$COMMITTER_TOKEN@github.com/$HEAD_REPO.git

set -o xtrace

git fetch origin $BASE_BRANCH
git fetch fork $HEAD_BRANCH

git checkout -b fork/$HEAD_BRANCH fork/$HEAD_BRANCH
if [[ $INPUT_AUTOSQUASH -eq 'true' ]]; then
	GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/$BASE_BRANCH
else
	git rebase origin/$BASE_BRANCH
fi

git push --force-with-lease fork origin/$HEAD_BRANCH:$HEAD_BRANCH
git checkout -b origin/$BASE_BRANCH origin/$BASE_BRANCH
git merge fork/$HEAD_BRANCH
git fetch
git push --force-with-lease origin origin/$BASE_BRANCH:$BASE_BRANCH

