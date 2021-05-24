#!/bin/bash

# Setup: 
# Copy the example env file at `.env.example` to .env, and fill the values of your own variables
# TEAMS_BUMP_WEBHOOK: a url that you setup following the procudure at https://stackoverflow.com/a/65759554
# TWINE_USERNAME: your Pypi username
# TWINE_PASSWORD: your Pypi password

# How to run:
# $ (source .env && ./bumpversion.sh patch)
# Can pass in test, patch, minor, or major depending on which part of the version you're bumping. We
# roughly follow semantic versioning:
# * test is a nonstandard version increment. Since you have to install Docassemble packages to test 
#   if they work in other packages, you should bump test before installing to see what works
# * patch is a version that changes nothing about how other interviews use your package/library.
#   Usually just bug fixes.
# * minor is the addition of a feature, and generally means that you cannot downgrade after upgrading
# * major is a breaking change, either internally or externally
# For more info about semantic versioning (aka semver), see https://semver.org/

set -euo pipefail

### Make sure you have all the necessary commands installed and env vars set
git --help 2>&1 > /dev/null
bumpversion --help 2>&1 > /dev/null
twine --help 2>&1 > /dev/null
test ! -z $TWINE_USERNAME
test ! -z $TWINE_PASSWORD
test ! -z $TEAMS_BUMP_WEBHOOK

### Makes git commit and tag
if [ "$1" = "minor" ] || [ "$1" = "major" ] 
then
  echo What has changed about this "$1" version?
  read -r release_update
  new_version=$(bumpversion --config-file .bumpversion.cfg "$1" --list | grep new_version | cut -d= -f 2)
  echo -e "# Version v$new_version\n\n$release_update\n\n$(cat CHANGELOG.md)" > CHANGELOG.md
  git add CHANGELOG.md && git commit --amend -C HEAD
else
  new_version=$(bumpversion --config-file .bumpversion.cfg "$1" --list | grep new_version | cut -d= -f 2)
fi
git push 
git push --tags

### Make and update Pypi package
rm -rf build dist ./*.egg-info
python3 setup.py sdist
# Needs TWINE_USERNAME and TWINE_PASSWORD
twine upload --repository 'pypi' dist/* --non-interactive
rm -rf build dist ./*.egg-info

### Auto get project and repo name to put in Teams message
remote_url=$(git remote -v | cut -f2 | cut -d ' ' -f1)
repo_name=$(basename -s "$remote_url")
org_name=$(basename "$(dirname "$remote_url")")
if [[ "$org_name" = *@* ]]; then
  # Likely an SSH URL. Split at the ':'
  org_name=$(echo "$org_name" | cut -d ':' -f2)
fi
project_name=$(echo "$repo_name" | cut -d - -f2)

# This JSON was built using: https://messagecardplayground.azurewebsites.net/, 
# and https://docs.microsoft.com/en-us/outlook/actionable-messages/message-card-reference
sed -e "s/{{version}}/$new_version/g; s/{{project_name}}/$project_name/g; s/{{org_name}}/$org_name/g; s/{{repo_name}}/$repo_name/g;" << EOF > /tmp/teams_msg_to_send.json
{
	"@type": "MessageCard",
	"@context": "https://schema.org/extensions",
	"summary": "{{project_name}} Version released",
	"themeColor": "0078D7",
	"title": "{{project_name}} Version {{version}} released", 
	"sections": [
		{
			"activityTitle": "Version {{version}}",
			"activityImage": "https://avatars.githubusercontent.com/u/33028765?s=200&v=4", 
			"facts": [
				{
					"name": "Repository:",
					"value": "{{org_name}}/{{repo_name}}"
				},
				{
					"name": "Tag",
					"value": "v{{version}}"
				}
			],
			"text": "" 
		}
	],
	"potentialAction": [
        {
            "@type": "OpenUri",
            "name": "See Changelog",
            "targets": [
                {
                    "os": "default",
                    "uri": "https://github.com/{{org_name}}/{{repo_name}}/blob/v{{version}}/CHANGELOG.md#v{{version}}"
                }
            ]
        },
		{
			"@type": "OpenUri",
			"name": "View in GitHub",
			"targets": [
				{
					"os": "default",
					"uri": "http://github.com/{{org_name}}/{{repo_name}}/releases/tag/v{{version}}"
				}
			]
		}
	]
}
EOF

curl -H "Content-Type:application/json" -d "@/tmp/teams_msg_to_send.json" "$TEAMS_BUMP_WEBHOOK"
rm "/tmp/teams_msg_to_send.json"

