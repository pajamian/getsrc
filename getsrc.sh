#!/bin/bash

# Skip's "universal" lookaside grabber
#
# Run this in a Fedora/Rocky/CentOS/CentOS Stream source directory, and it will retrieve the lookaside sources (tarballs) into the current directory
#

shopt -s nullglob

# List of lookaside locations and their patterns
# This can be easily edited to add more distro locations, or change their order for less 404 misses:
lookasides=(
https://rocky-linux-sources-staging.a1.rockylinux.org/%HASH%
https://sources.build.resf.org/%HASH%
https://git.centos.org/sources/%PKG%/%BRANCH%/%HASH%
https://sources.stream.centos.org/sources/rpms/%PKG%/%FILENAME%/%SHATYPE%/%HASH%/%FILENAME%
https://src.fedoraproject.org/repo/pkgs/%PKG%/%FILENAME%/%SHATYPE%/%HASH%/%FILENAME%
)

declare -A macros

###
# Function that actually downloads a lookaside source
# Takes HASH / FILENAME / BRANCH / PKG / SHATYPE as arguments $1 / $2 / $3 / $4 / $5
function download {
    for url in "${lookasides[@]}"; do
	# Substitute each of our macros (%PKG%, %HASH%, etc.):
	for k in "${!macros[@]}"; do
	    v=${macros[$k]}
	    url=${url//"%$k%"/$v}
	done

	# Download the file with curl, return if successful.
	if curl --create-dirs -sfLo "${macros[FILENAME]}" "$url"; then
	    printf 'Downloaded: %s  ----->  %s\n' "$url" "${macros[FILENAME]}"
	    return
	fi
    done

    echo "ERROR: Unable to find lookaside file with the following HASH / FILENAME / BRANCH / PKG / SHATYPE :"
    echo "${macros[HASH]}  /  ${macros[FILENAME]}  /  ${macros[BRANCH]}  /  ${macros[PKG]}  /  ${macros[SHATYPE]}"
    exit 1
}




###
# discover our list of lookaside sources.  They are either in a "sources" file (new), or the older ".packagename.metadata" format (old)
sourcesfiles=(.*.metadata sources)
mapfile -t sourcelines < <(cat "${sourcesfiles[@]}" 2>/dev/null)

if (( ${#sourcelines[@]} == 0 )); then
  echo "ERROR: Cannot find .*.metadata or sources file listing sources.  Are you in the right directory?"
  exit 1
fi


# Current git branch.  We don't error out if this fails, as we may not necessarily need this info
macros[BRANCH]=$(git status | sed -n 's/.*On branch //p')



# Source package name should match the specfile - we'll use that in lieu of parsing "Name:" out of it
# There could def. be a better way to do this....
# UPDATE: The better way is to use rpmspec, but this may not be installed, so
# fall back to the old way if it isn't.
specfile=(SPECS/*.spec)
if (( ${#specfile[@]}!= 1 )); then
    echo "ERROR: Exactly one spec file expected, ${#specfile[@]} found."
    exit 1
fi

macros[PKG]=$(rpmspec -q --qf '%{NAME}\n' --srpm "${specfile[0]}") || {
    pkg=${specfile[0]##*/}
    macros[PKG]=${pkg%.spec}
}

if (( ${#macros[PKG]} < 2 )); then
  echo "ERROR: Having trouble finding the name of the package based on the name of the .spec file."
  exit 1
fi



# Loop through each line of our looksaide, and download the file:
for line in "${sourcelines[@]}"; do
  
  # First, we need to discover whether this is a new or old style hash.  New style has 4 fields "SHATYPE (NAME) = HASH", old style has 2: "HASH NAME"
  if [[ $(echo "$line" | awk '{print NF}') -eq 4 ]]; then
    macros[HASH]=$(echo "$line" | awk '{print $4}')
    macros[FILENAME]=$(echo "$line" | awk '{print $2}' | tr -d ')' | tr -d '(')
  
  # Old style hash: "HASH FILENAME"
  elif [[ $(echo "$line" | awk '{print NF}') -eq 2 ]]; then
    macros[HASH]=$(echo "$line" | awk '{print $1}')
    macros[FILENAME]=$(echo "$line" | awk '{print $2}')
  
  # Skip a line if it's blank or just an empty one
  elif [[ $(echo "$line" | wc -c) -lt 3 ]]; then
    continue

  else
    echo "ERROR: This lookaside line does not appear to have 2 or 4 space-separated fields.  I don't know how to parse this line:"
    echo "${line}"
    exit 1
  fi
    
  
  macros[SHATYPE]=""
  # We have a hash and a filename, now we need to find the hash type (based on string length):
  case ${#macros[HASH]} in 
    "33")
      macros[SHATYPE]="md5"
      ;;
    "41")
      macros[SHATYPE]="sha1"
      ;;
    "65")
      macros[SHATYPE]="sha256"
      ;;
    "97")
      macros[SHATYPE]="sha384"
      ;;
    "129")
      macros[SHATYPE]="sha512"
      ;;
  esac
    

  # Finally, we have all our information call the download function with the relevant variables:
  download


done
