#!/bin/sh
set -eu

api_base=${VERS_API_BASE:-https://api.vers.sh/api/v1}

usage() {
    echo "Usage: cleanup-vers-review.sh VM_ID_FILE" >&2
}

if [ "$#" -ne 1 ]; then
    usage
    exit 2
fi
if [ -z "${VERS_API_KEY:-}" ]; then
    echo "VERS_API_KEY is required" >&2
    exit 1
fi

vm_id_file=$1
if [ ! -s "$vm_id_file" ]; then
    echo "No disposable review VM was recorded"
    exit 0
fi

vm_id=$(sed -n '1p' "$vm_id_file")
case "$vm_id" in
    *[!0-9a-f-]*|'')
        echo "Invalid review VM ID in $vm_id_file" >&2
        exit 1
        ;;
esac

echo "Deleting disposable review VM $vm_id"
http_status=$(
    curl --silent --show-error \
        --retry 5 --retry-all-errors \
        --output /dev/null \
        --write-out '%{http_code}' \
        -X DELETE \
        -H "Authorization: Bearer $VERS_API_KEY" \
        "$api_base/vm/$vm_id"
)

case "$http_status" in
    2??|404)
        rm -f "$vm_id_file"
        ;;
    *)
        echo "Vers returned HTTP $http_status while deleting VM $vm_id" >&2
        exit 1
        ;;
esac
