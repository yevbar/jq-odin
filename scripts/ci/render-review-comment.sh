#!/bin/sh
set -eu

result_file=${1:?assessment result is required}
repository=${2:?repository name is required}
head_sha=${3:?head SHA is required}
run_url=${4:?workflow run URL is required}

jq -e '
    (
      .recommendation == "merge_as_is" and
      .quality_score >= 4 and
      (.confidence == "medium" or .confidence == "high") and
      (.findings | length == 0)
    ) or (
      .recommendation == "task_agent" and
      (.findings | length > 0)
    )
' "$result_file" >/dev/null

jq -r \
    --arg repository "$repository" \
    --arg head_sha "$head_sha" \
    --arg run_url "$run_url" '
    def html:
      gsub("&"; "&amp;")
      | gsub("<"; "&lt;")
      | gsub(">"; "&gt;")
      | gsub("@"; "&#64;")
      | gsub("[\r\n]+"; "<br>");
    def location:
      (.path | html) +
      (if .line == null then "" else ":" + (.line | tostring) end);
    def finding:
      "<h3>[" + (.severity | ascii_upcase) + "] " +
        (.title | html) + "</h3>\n\n" +
      "**Location:** <code>" + location + "</code>\n\n" +
      "**Evidence:** <p>" + (.evidence | html) + "</p>\n\n" +
      "**Failure mode:** <p>" + (.failure_mode | html) + "</p>";

    [
      "<!-- jq-adversarial-assessment head=" + $head_sha + " -->",
      "## Adversarial diff assessment",
      "",
      "**Head:** [`" + ($head_sha[0:12]) + "`](https://github.com/" +
        $repository + "/commit/" + $head_sha + ")  ",
      "**Quality:** " + (.quality_score | tostring) + "/5  ",
      "**Confidence:** " + .confidence + "  ",
      "**Recommendation:** `" + .recommendation + "`",
      "",
      "<p>" + (.summary | html) + "</p>",
      "",
      "### Findings",
      ""
    ] +
    (if (.findings | length) == 0
     then ["None."]
     else [.findings[] | finding]
     end) +
    [
      "",
      "[Workflow run](" + $run_url + ") · The recommendation is advisory; " +
        "the integration coordinator owns disposition."
    ]
    | join("\n")
' "$result_file"
