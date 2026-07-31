#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/run-vers-review-test.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM

fake_bin="$test_dir/bin"
packet_dir="$test_dir/packet"
capture_dir="$test_dir/captures"
tmp_dir="$test_dir/tmp"
mkdir "$fake_bin" "$packet_dir" "$capture_dir" "$tmp_dir"

cat >"$fake_bin/curl" <<'EOF'
#!/bin/sh
set -eu

method=GET
body_arg=
url=
expect_body_file=false
key_in_argv=false
expect_header=false
auth_seen=false
for arg do
    if [ "${#arg}" -gt 131072 ]; then
        echo "curl received an oversized argument (${#arg} bytes)" >&2
        exit 90
    fi
    if [ "$arg" = "Authorization: Bearer $VERS_API_KEY" ]; then
        key_in_argv=true
    fi
    if [ "$expect_header" = true ]; then
        case "$arg" in
            @*)
                if grep -Fqx "Authorization: Bearer $VERS_API_KEY" "${arg#@}"; then
                    auth_seen=true
                fi
                ;;
            "Authorization: Bearer $VERS_API_KEY")
                auth_seen=true
                ;;
        esac
        expect_header=false
        continue
    fi
    if [ "$expect_body_file" = true ]; then
        body_arg=$arg
        expect_body_file=false
        continue
    fi
    case "$arg" in
        -X)
            expect_method=true
            ;;
        -H)
            expect_header=true
            ;;
        --data|--data-binary)
            expect_body_file=true
            ;;
        http://*)
            url=$arg
            ;;
        *)
            if [ "${expect_method:-false}" = true ]; then
                method=$arg
                expect_method=false
            fi
            ;;
    esac
done

if [ "$method" != DELETE ]; then
    if [ "$key_in_argv" = true ]; then
        echo "controller curl received the API key in an argument" >&2
        exit 89
    fi
    if [ "$auth_seen" != true ]; then
        echo "controller curl omitted the authentication header" >&2
        exit 88
    fi
fi

case "$method:$url" in
    POST:*/vm/from_commit)
        printf '{"vm_id":"11111111-1111-4111-8111-111111111111"}'
        ;;
    GET:*/vm/11111111-1111-4111-8111-111111111111/status)
        printf '{"state":"running"}'
        ;;
    PUT:*/vm/11111111-1111-4111-8111-111111111111/files)
        case "$body_arg" in
            @*) body_file=${body_arg#@} ;;
            *) echo "upload body was not supplied from a file" >&2; exit 91 ;;
        esac
        if [ "${FAKE_FAIL_UPLOAD:-false}" = true ]; then
            exit 93
        fi
        count_file="$FAKE_CAPTURE_DIR/count"
        count=0
        if [ -f "$count_file" ]; then
            count=$(sed -n '1p' "$count_file")
        fi
        count=$((count + 1))
        printf '%s\n' "$count" >"$count_file"
        cp "$body_file" "$FAKE_CAPTURE_DIR/upload-$count.json"
        printf '{}'
        ;;
    POST:*/vm/11111111-1111-4111-8111-111111111111/exec)
        if printf '%s' "$body_arg" |
            jq -e '.command[2] | contains("run-review.sh")' >/dev/null 2>&1; then
            printf '{"exit_code":0,"stdout":"","stderr":""}'
        else
            printf '{"exit_code":0,"stdout":"0\\n","stderr":""}'
        fi
        ;;
    GET:*/vm/11111111-1111-4111-8111-111111111111/files)
        result='{"recommendation":"merge_as_is","quality_score":5,"confidence":"high","summary":"ok","findings":[]}'
        content=$(printf '%s' "$result" | base64 | tr -d '\n')
        jq -cn --arg content "$content" '{content_b64: $content}'
        ;;
    DELETE:*/vm/11111111-1111-4111-8111-111111111111)
        printf '204'
        ;;
    *)
        echo "unexpected curl request: $method $url" >&2
        exit 92
        ;;
esac
EOF
chmod 755 "$fake_bin/curl"

for file in manifest.txt files.tsv PROMPT.md result.schema.json; do
    printf '%s\n' "$file fixture" >"$packet_dir/$file"
done
awk 'BEGIN { for (i = 0; i < 300000; i++) printf "%c", 65 + (i % 26) }' \
    >"$packet_dir/change.diff"

PATH="$fake_bin:$PATH" \
FAKE_CAPTURE_DIR="$capture_dir" \
TMPDIR="$tmp_dir" \
VERS_API_BASE=http://vers.test/api/v1 \
VERS_API_KEY=test-only \
VERS_VM_ID_FILE="$test_dir/vm-id" \
    "$script_dir/run-vers-review.sh" "$packet_dir" "$test_dir/result.json"

test "$(sed -n '1p' "$capture_dir/count")" -eq 6
large_upload=
for upload in "$capture_dir"/upload-*.json; do
    jq -e '
        (.path | type == "string") and
        (.content_b64 | type == "string" and test("^[A-Za-z0-9+/]*={0,2}$")) and
        (.create_dirs == true) and
        (.mode | type == "number")
    ' "$upload" >/dev/null
    if [ "$(jq -r .path "$upload")" = /tmp/jq-review/change.diff ]; then
        large_upload=$upload
    fi
done

test -n "$large_upload"
test "$(jq -r .mode "$large_upload")" -eq 420
if jq -r .content_b64 "$large_upload" |
    base64 --decode >"$test_dir/decoded.diff" 2>/dev/null; then
    :
else
    jq -r .content_b64 "$large_upload" | base64 -D >"$test_dir/decoded.diff"
fi
cmp "$packet_dir/change.diff" "$test_dir/decoded.diff"

review_script_upload=
for upload in "$capture_dir"/upload-*.json; do
    if [ "$(jq -r .path "$upload")" = /tmp/jq-review/run-review.sh ]; then
        review_script_upload=$upload
    fi
done
test -n "$review_script_upload"
test "$(jq -r .mode "$review_script_upload")" -eq 493
jq -e . "$test_dir/result.json" >/dev/null
test ! -e "$test_dir/vm-id"
test -z "$(find "$tmp_dir" -name 'vers-review-upload.*' -print -quit)"

failure_capture_dir="$test_dir/failure-captures"
failure_tmp_dir="$test_dir/failure-tmp"
mkdir "$failure_capture_dir" "$failure_tmp_dir"
if PATH="$fake_bin:$PATH" \
    FAKE_CAPTURE_DIR="$failure_capture_dir" \
    FAKE_FAIL_UPLOAD=true \
    TMPDIR="$failure_tmp_dir" \
    VERS_API_BASE=http://vers.test/api/v1 \
    VERS_API_KEY=test-only \
    VERS_VM_ID_FILE="$test_dir/failure-vm-id" \
        "$script_dir/run-vers-review.sh" \
        "$packet_dir" "$test_dir/failure-result.json"; then
    echo "Expected a rejected upload to fail the controller" >&2
    exit 1
fi
test ! -e "$test_dir/failure-vm-id"
test -z "$(find "$failure_tmp_dir" -name 'vers-review-upload.*' -print -quit)"
