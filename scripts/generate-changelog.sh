#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# make sure jq is installed
if ! command -v jq &> /dev/null
then
    echo "jq could not be found"
    exit
fi

# make sure curl is installed
if ! command -v curl &> /dev/null
then
    echo "curl could not be found"
    exit
fi

# make sure ../debian exists
if [ ! -f $SCRIPT_DIR/../debian ]; then
    mkdir -p $SCRIPT_DIR/../debian
fi

# Get all releases from github
RELEASES=$(curl -s https://api.github.com/repos/brianmiller/phvalheim-client/releases)

# Delete the changelog if it exists
if [ -f $SCRIPT_DIR/../debian/changelog ]; then
    rm $SCRIPT_DIR/../debian/changelog
fi

# For each realease, get the tag name, body, author, date and seperate the version into major, minor and patch
for release in $(echo $RELEASES | jq -r '.[] | @base64'); do
    _jq() {
        echo ${release} | base64 --decode | jq -r ${1}
    }

    TAG_NAME=$(_jq '.tag_name')
    BODY=$(_jq '.body')
    AUTHOR=$(_jq '.author.login')
    EMAIL=$(_jq '.author.html_url')
    DATE=$(_jq '.published_at')

    # Format the date like this: Wed, 21 Oct 2015 07:28:00 -0700
    DATE=$(date -d $DATE +"%a, %d %b %Y %H:%M:%S %z")

    MAJOR=$(echo $TAG_NAME | cut -d"." -f1)
    MINOR=$(echo $TAG_NAME | cut -d"." -f2)
    PATCH=$(echo $TAG_NAME | cut -d"." -f3)

    # Write the changelog to ../debian/changelog
    echo "phvalheim-client ($TAG_NAME) stable; urgency=low" >> $SCRIPT_DIR/../debian/changelog
    echo "" >> $SCRIPT_DIR/../debian/changelog
    
    # For each line in the body, remove whitespace from beginning and end of line
    # if line is not empty, and line is less than 80 characters, and the previous line was empty, then add the line to the changelog enclosed in []
    # otherwise, add the line as a bullet point
    while IFS= read -r line; do
        line=$(echo $line | sed 's/^[[:space:]]*//g' | sed 's/[[:space:]]*$//g')
        if [ ! -z "$line" ]; then
            if [ ! -z "$line" ] && [ ${#line} -lt 80 ] && ([ -z "$prev_line" ] || [ -z "$prev_line" ] || [ -z "$prev_line" ]); then
                echo "  [$line]" >> $SCRIPT_DIR/../debian/changelog
            else
                echo "  *  $line" >> $SCRIPT_DIR/../debian/changelog
            fi
        fi
        prev_line=$line
    done <<< "$BODY"

    echo "" >> $SCRIPT_DIR/../debian/changelog
    echo " -- $AUTHOR <$EMAIL>  $DATE" >> $SCRIPT_DIR/../debian/changelog
    echo "" >> $SCRIPT_DIR/../debian/changelog
done