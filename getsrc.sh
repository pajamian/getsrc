#!/bin/bash

# Skip's "universal" lookaside grabber
#
# Run this in a Fedora/Rocky/CentOS/CentOS Stream source directory, and it will retrieve the lookaside sources (tarballs) into the current directory
#

IFS='
'


# List of lookaside locations and their patterns
# This can be easily edited to add more distro locations, or change their order for less 404 misses:
lookasides=(
https://rocky-linux-sources-staging.a1.rockylinux.org/%HASH%
https://sources.build.resf.org/%HASH%
https://git.centos.org/sources/%PKG%/%BRANCH%/%HASH%
https://sources.stream.centos.org/sources/rpms/%PKG%/%FILENAME%/%SHATYPE%/%HASH%/%FILENAME%
https://src.fedoraproject.org/repo/pkgs/%PKG%/%FILENAME%/%SHATYPE%/%HASH%/%FILENAME%
)



###
# Function that actually downloads a lookaside source
# Takes HASH / FILENAME / BRANCH / PKG / SHATYPE as arguments $1 / $2 / $3 / $4 / $5
function download {
  
  foundFile=0

  for site in "${lookasides[@]}"; do
    url="$site"

    # Substitute each of our macros (%PKG%, %HASH%, etc.):
    url=$(echo "${url}" | sed "s|%HASH%|${1}|g")
    url=$(echo "${url}" | sed "s|%FILENAME%|${2}|g")
    url=$(echo "${url}" | sed "s|%BRANCH%|${3}|g")
    url=$(echo "${url}" | sed "s|%PKG%|${4}|g")
    url=$(echo "${url}" | sed "s|%SHATYPE%|${5}|g")
    

    # Use curl to get just the header info of the remote file
    retCode=$(curl -o /dev/null --silent -Iw '%{http_code}' "${url}")
    
    # Download the file only if we get a 3-character http return code (200, 301, 302, 404, etc.) 
    # AND the code must begin with 2 or 3, to indicate 200 FOUND, or some kind of 3XX redirect
    if [[ $(echo "${retCode}" | wc -c) -eq 4  && ( $(echo "${retCode}" | cut -c1-1) == "2" || $(echo "${retCode}" | cut -c1-1) == "3" ) ]]; then
       curl --silent --create-dirs -o "${2}" "${url}"
       echo "Downloaded: ${url}  ----->  ${2}"
       foundFile=1
       break
    fi
  done

  if [[ "${foundFile}" == "0" ]]; then
    echo "ERROR: Unable to find lookaside file with the following HASH / FILENAME / BRANCH / PKG / SHATYPE :"
    echo "$1  /  $2  /  $3  /  $4  /  $5"
    exit 1
  fi

}




###
# discover our list of lookaside sources.  They are either in a "sources" file (new), or the older ".packagename.metadata" format (old)
SOURCES=$(cat .*.metadata sources 2> /dev/null) 

if [[ $(echo "$SOURCES" | wc -c) -lt 10 ]]; then
  echo "ERROR: Cannot find .*.metadata or sources file listing sources.  Are you in the right directory?"
  exit 1
fi


# Current git branch.  We don't error out if this fails, as we may not necessarily need this info
BRANCH=$(git status | sed -n 's/.*On branch //p')



# Source package name should match the specfile - we'll use that in lieu of parsing "Name:" out of it
# There could def. be a better way to do this....
PKG=$(find . -iname *.spec | head -1 | xargs -n 1 basename | sed 's/\.spec//')

if [[ $(echo "$PKG" | wc -c) -lt 2 ]]; then
  echo "ERROR: Having trouble finding the name of the package based on the name of the .spec file."
  exit 1
fi



# Loop through each line of our looksaide, and download the file:
for line in $(echo "$SOURCES"); do
  
  # First, we need to discover whether this is a new or old style hash.  New style has 4 fields "SHATYPE (NAME) = HASH", old style has 2: "HASH NAME"
  if [[ $(echo "$line" | awk '{print NF}') -eq 4 ]]; then
    HASH=$(echo "$line" | awk '{print $4}')
    FILENAME=$(echo "$line" | awk '{print $2}' | tr -d ')' | tr -d '(')
  
  # Old style hash: "HASH FILENAME"
  elif [[ $(echo "$line" | awk '{print NF}') -eq 2 ]]; then
    HASH=$(echo "$line" | awk '{print $1}')
    FILENAME=$(echo "$line" | awk '{print $2}')
  
  # Skip a line if it's blank or just an empty one
  elif [[ $(echo "$line" | wc -c) -lt 3 ]]; then
    continue

  else
    echo "ERROR: This lookaside line does not appear to have 2 or 4 space-separated fields.  I don't know how to parse this line:"
    echo "${line}"
    exit 1
  fi
    
  
  SHATYPE=""
  # We have a hash and a filename, now we need to find the hash type (based on string length):
  case $(echo "$HASH" | wc -c) in 
    "33")
      SHATYPE="md5"
      ;;
    "41")
      SHATYPE="sha1"
      ;;
    "65")
      SHATYPE="sha256"
      ;;
    "97")
      SHATYPE="sha384"
      ;;
    "129")
      SHATYPE="sha512"
      ;;
  esac
    

  # Finally, we have all our information call the download function with the relevant variables:
  download "${HASH}"  "${FILENAME}"  "${BRANCH}"  "${PKG}"  "${SHATYPE}"


done
