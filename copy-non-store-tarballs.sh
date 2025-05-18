# https://nix.dev/manual/nix/2.25/command-ref/new-cli/nix3-derivation-add.html?highlight=hashAlgo#derivation-json-format
# This gives some details on the fields used below.
# Test whether it works for a derivation by blacklisting (eg. by setting
# networking.extraHosts = "0.0.0.0 <url>", temporarily) all urls listed for
# some resources, and calling
# ```bash
# sudo NIX_HASHED_MIRRORS="custom mirror url" nix build <derivation>
# ```
# sudo is required because we have to pass an env-var to nix build, and if it's
# called as a regular user, the build will (likely) be executed by the nix
# daemon, and it does not receive NIX_HASHED_MIRRORS (alternatively, set the
# env-var in the systemd service of the nix daemon).

set -eo pipefail

function help {
	echo ""
	echo "Supply a derivation and a rclone-compatible destination as the first two arguments."
	echo "The third argument are additional flags passed to rclone."
	echo "Examples:"
	echo "  copy-non-store-tarballs /run/current-system 's3-bucket:/bucketname' '-P --config ./rclone.conf'"
	echo "  copy-non-store-tarballs .#devShells.x86_64-linux.default 's3-bucket:/bucketname' '-P --config ./rclone.conf'"
	echo ""
}

trap cleanup EXIT

if [ ! -v 1 ] || [ ! -v 2 ]; then
	help
	exit
fi

DERIVATION=$1
TARBALL_DESTINATION=$2
RCLONE_FLAGS=""

if [ -v 3 ]; then
	RCLONE_FLAGS=$3
fi

DL_DIR=$(mktemp -d)

function cleanup {
	rm -rf "$DL_DIR"
}

# don't split!
IFS=$''
FODS=$(nix derivation show -r "$DERIVATION" | jq -r '.[] | select(.outputs.out.hash and (.env.url or .env.urls)) | .outputs.out.method + " " + .outputs.out.hashAlgo + " " + .outputs.out.hash + " " + .outputs.out.path + " " + (if .env.url then .env.url else  .env.urls end)' | sort -u)

IFS=$'\n'
for f in $FODS
do
	HASHMETHOD="$(echo "$f" | cut -d ' ' -f 1)"
	HASHALGO="$(echo "$f" | cut -d ' ' -f 2)"
	HASH="$(echo "$f" | cut -d ' ' -f 3)"
	STORE_PATH="$(echo "$f" | cut -d ' ' -f 4)"
	URLS="$(echo "$f" | cut -d ' ' -f 5-)"

	# check whether cache.nixos.org or tarballs.nixos.org have the file.
	if [ "$(nix path-info --store https://cache.nixos.org --recursive "$STORE_PATH" 2> /dev/null)" == "" ] && ! wget -q --method HEAD "https://tarballs.nixos.org/$HASHALGO/$HASH"; then
		echo ""
		echo "Found $STORE_PATH missing from cache.nixos.org and tarballs.nixos.org!"

		FILE_PATH=""
		if [ ! -f "$STORE_PATH" ]; then
			echo "$STORE_PATH is not in the local store, attempting download from $URLS."
			DL_LOCATION="$DL_DIR/$HASH"
			# File is not downloaded => check all urls we have.
			IFS=$' '
			for url in $URLS
			do
				if wget "$url" -O "$DL_LOCATION"; then
					echo "Downloaded $STORE_PATH from $url to $DL_LOCATION"
					FILE_PATH="$DL_LOCATION"
					break
				fi
			done
		else
			echo "Found $STORE_PATH in the local store."
			FILE_PATH="$STORE_PATH"
		fi

		if [ -z "$FILE_PATH" ]; then
			echo "$STORE_PATH does not exists locally, and at $URLS, skipping it."
			continue
		fi
		# we have the file, copy it to $TARBALL_DESTINATION if the hash
		# matches.

		# Build flags for nix-hash.
		# Apparently, FODs always use a base16 string.
		NIX_HASH_FLAGS="--base16 --type $HASHALGO"
		case $HASHMETHOD in
			nar)
				# nar is the default-mode of nix-hash, does not need any flags.
				;;
			flat | text)
				NIX_HASH_FLAGS="$NIX_HASH_FLAGS --flat"
				;;
			*)
				echo "Cannot handle hash-method $HASHMETHOD"
				;;
		esac

		# set IFS so NIX_HASH_FLAGS are split properly.
		IFS=$' '
		# shellcheck disable=SC2086
		ACTUAL_HASH=$(nix-hash $NIX_HASH_FLAGS "$FILE_PATH")

		if [ ! "$HASH" == "$ACTUAL_HASH" ]; then
			echo "Expected hash $HASH, file $FILE_PATH ($STORE_PATH, $URLS) has hash $ACTUAL_HASH. Skipping it."
			continue
		fi

		echo "Copying $STORE_PATH to $TARBALL_DESTINATION as $HASHALGO/$HASH."
		# shellcheck disable=SC2086
		rclone copyto $RCLONE_FLAGS "$FILE_PATH" "$TARBALL_DESTINATION/$HASHALGO/$HASH"
	fi
done
