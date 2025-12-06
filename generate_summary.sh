#!/bin/bash

set -e

REPORT_PATH="${1:-analysis-results/compliance_report.txt}"

echo "## CBOM Analysis Results" >> "$GITHUB_STEP_SUMMARY"
echo "Analysis completed at: $(date)" >> "$GITHUB_STEP_SUMMARY"
echo "### Repository Analyzed" >> "$GITHUB_STEP_SUMMARY"
echo "Repository: ${GITHUB_REPOSITORY}" >> "$GITHUB_STEP_SUMMARY"
echo "Branch: ${GITHUB_REF#refs/heads/}" >> "$GITHUB_STEP_SUMMARY"
echo "Commit: ${GITHUB_SHA}" >> "$GITHUB_STEP_SUMMARY"
echo "" >> "$GITHUB_STEP_SUMMARY"

if [ ! -f "$REPORT_PATH" ]; then
  echo "### Compliance report not found." >> "$GITHUB_STEP_SUMMARY"
  echo "No violations found." >> "$GITHUB_STEP_SUMMARY"
  echo "" >> "$GITHUB_STEP_SUMMARY"
  echo "### Full Reports" >> "$GITHUB_STEP_SUMMARY"
  echo "- CBOM Report (cbom.json)" >> "$GITHUB_STEP_SUMMARY"
  echo "- Compliance Report (compliance_report.txt)" >> "$GITHUB_STEP_SUMMARY"
  exit 0
fi

TOTAL_VIOLATIONS=$(grep "Found [0-9]* violation" "$REPORT_PATH" | grep -o '[0-9]*' | head -1)
[ -z "$TOTAL_VIOLATIONS" ] && TOTAL_VIOLATIONS=0

echo "### Security Violations Found" >> "$GITHUB_STEP_SUMMARY"
echo "**Total violations found: $TOTAL_VIOLATIONS**" >> "$GITHUB_STEP_SUMMARY"
echo "" >> "$GITHUB_STEP_SUMMARY"

if [ "$TOTAL_VIOLATIONS" -gt 0 ]; then
  awk -v summary="$GITHUB_STEP_SUMMARY" '
    BEGIN {
      violation_count = 0; in_violation = 0;
    }
    /^- Rule ID:/ {
      in_violation = 1;
      rule_id = $0;
      sub(/^- Rule ID:[[:space:]]*/, "", rule_id);
    }
    in_violation && /^  Description:/ {
      description = $0;
      sub(/^  Description:[[:space:]]*/, "", description);
    }
    in_violation && /^  Location:/ {
      location = $0;
      sub(/^  Location:[[:space:]]*/, "", location);
      split(location, loc_parts, ":");
      file = loc_parts[1]; line = loc_parts[2];
    }
    in_violation && /^  Finding:/ {
      finding = $0;
      sub(/^  Finding:[[:space:]]*/, "", finding);
    }
    in_violation && /^$/ {
      if (rule_id && description && file && line) {
        violation_count++;
        severity = "Medium";
        if (index(description, "DES")) severity = "High";
        if (index(description, "MD5")) severity = "Medium";
        if (index(description, "SHA1")) severity = "Medium";
        if (index(description, "RC4")) severity = "High";

        print "#### Violation in `" file "` at line " line >> summary;
        print "**Rule**: " rule_id >> summary;
        print "**Severity**: " severity >> summary;
        print "**Description**: " description >> summary;
        print "" >> summary;
        print "**Affected Code:**" >> summary;
        print "```c" >> summary;

        start_line = line - 3; end_line = line + 3;
        if (start_line < 1) start_line = 1;
        if (system("[ -f \"" file "\" ]") == 0) {
          cmd = "awk -v start=" start_line " -v end=" end_line " -v target=" line " \'NR >= start && NR <= end { if (NR == target) printf(\"→ %d: %s\\n\", NR, $0); else printf(\"  %d: %s\\n\", NR, $0); }\' " file;
          while ((cmd | getline code_line) > 0) {
            print code_line >> summary;
          }
          close(cmd);
        } else {
          print "File not found in workspace." >> summary;
        }

        print "```" >> summary;
        print "" >> summary;

        if (severity == "High") high_count++;
        else if (severity == "Medium") medium_count++;
        else if (severity == "Low") low_count++;
      }
      in_violation = 0;
      rule_id = ""; description = ""; location = "";
      file = ""; line = ""; finding = "";
    }
    END {
      print "### Violation Statistics" >> summary;
      print "**Total violations**: " violation_count >> summary;
      print "" >> summary;
      print "**By severity:**" >> summary;
      if (high_count > 0) print "- High: " high_count >> summary;
      if (medium_count > 0) print "- Medium: " medium_count >> summary;
      if (low_count > 0) print "- Low: " low_count >> summary;
      print "" >> summary;
    }
  ' "$REPORT_PATH"
else
  echo "No violations found." >> "$GITHUB_STEP_SUMMARY"
  echo "" >> "$GITHUB_STEP_SUMMARY"
fi

echo "### Full Reports" >> "$GITHUB_STEP_SUMMARY"
echo "- CBOM Report (cbom.json)" >> "$GITHUB_STEP_SUMMARY"
echo "- Compliance Report (compliance_report.txt)" >> "$GITHUB_STEP_SUMMARY"
echo "" >> "$GITHUB_STEP_SUMMARY"
echo "**Job summary generated at run-time**" >> "$GITHUB_STEP_SUMMARY"
