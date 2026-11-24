#!/usr/bin/env bash
# DevTrack API smoke tests.
#
# Usage:
#   1. Start the server:  python manage.py runserver
#   2. Run:               ./tests.sh --reset        (deletes issues.json / reporters.json first)
#                         ./tests.sh > test_output.txt   to save the output for the README
#
# Set BASE to test another host:  BASE=http://127.0.0.1:9000/api ./tests.sh --reset

BASE="${BASE:-http://127.0.0.1:8000/api}"
cd "$(dirname "$0")" || exit 1

if [[ "$1" == "--reset" ]]; then
  rm -f issues.json reporters.json
fi
if [[ -e issues.json || -e reporters.json ]]; then
  echo "issues.json / reporters.json already exist. The tests expect a clean state."
  echo "Run again with:  ./tests.sh --reset"
  exit 1
fi
if ! curl -s -o /dev/null "$BASE/reporters/"; then
  echo "Cannot reach $BASE - is the server running (python manage.py runserver)?"
  exit 1
fi

PASS=0
FAIL=0

# run <expected_status> <title> <METHOD> <path> [json_body]
run() {
  local expected="$1" title="$2" method="$3" path="$4" body="$5"
  local args=(-s -w $'\n%{http_code}' -X "$method" "$BASE$path")
  local shown="curl -X $method '$BASE$path'"
  if [[ -n "$body" ]]; then
    args+=(-H 'Content-Type: application/json' -d "$body")
    shown+=" -H 'Content-Type: application/json' -d '$body'"
  fi

  local out code resp verdict
  out=$(curl "${args[@]}")
  code="${out##*$'\n'}"
  resp="${out%$'\n'*}"

  if [[ "$code" == "$expected" ]]; then
    verdict="PASS"; PASS=$((PASS + 1))
  else
    verdict="FAIL (expected $expected)"; FAIL=$((FAIL + 1))
  fi

  echo "### $title"
  echo "\$ $shown"
  if [[ "$resp" == *"<!DOCTYPE html>"* || "$resp" == *"<html"* ]]; then
    # Django debug page (server crashed): show only the exception, not the whole HTML
    local exc
    exc=$(printf '%s' "$resp" | grep -m1 -o '<pre class="exception_value">[^<]*' | sed 's/<pre class="exception_value">//')
    echo "(server crashed - HTML error page) $(printf '%s' "$resp" | grep -m1 -o '<title>[^<]*' | sed 's/<title>//'): $exc"
  else
    echo "$resp"
  fi
  echo "HTTP $code - $verdict"
  echo
}

section() { echo "=================== $1 ==================="; echo; }

# ---------------------------------------------------------------
section "1. Before any data exists"
run 200 "List reporters (empty)"            GET "/reporters/"
run 200 "List issues (empty)"               GET "/issues/"
run 404 "Reporter by id, none exist"        GET "/reporters/?id=1"
run 404 "Issue by id, none exist"           GET "/issues/?id=1"
run 404 "Issue when its reporter doesn't exist yet" POST "/issues/" \
  '{"id":1,"title":"t","description":"d","status":"open","priority":"high","reporter_id":1}'

# ---------------------------------------------------------------
section "2. Reporters - create"
run 201 "Create reporter 1"                 POST "/reporters/" \
  '{"id":1,"name":"Ada","email":"ada@x.com","team":"backend"}'
run 201 "Create reporter 2"                 POST "/reporters/" \
  '{"id":2,"name":"Bob","email":"bob@x.com","team":"frontend"}'
run 400 "Reporter with empty name"          POST "/reporters/" \
  '{"id":3,"name":"","email":"c@x.com","team":"devops"}'
run 400 "Reporter with invalid email"       POST "/reporters/" \
  '{"id":3,"name":"Cy","email":"no-at-sign","team":"devops"}'
run 400 "Reporter with non-string email"    POST "/reporters/" \
  '{"id":3,"name":"Cy","email":123,"team":"devops"}'
run 400 "Reporter with non-integer id"      POST "/reporters/" \
  '{"id":"abc","name":"Cy","email":"c@x.com","team":"devops"}'
run 400 "Reporter with missing fields"      POST "/reporters/" \
  '{"id":3,"name":"Cy"}'
run 400 "Reporter with duplicate id"        POST "/reporters/" \
  '{"id":1,"name":"Dup","email":"d@x.com","team":"ops"}'
run 400 "Reporter with invalid JSON body"   POST "/reporters/" 'not json'

# ---------------------------------------------------------------
section "3. Reporters - read"
run 200 "List all reporters"                GET "/reporters/"
run 200 "Reporter by id (2)"                GET "/reporters/?id=2"
run 404 "Reporter by id, not found"         GET "/reporters/?id=99"
run 400 "Reporter by non-numeric id"        GET "/reporters/?id=abc"
run 405 "Wrong method on reporters"         DELETE "/reporters/"

# ---------------------------------------------------------------
section "4. Issues - create (success)"
run 201 "Critical issue -> [URGENT] message" POST "/issues/" \
  '{"id":1,"title":"Login button not working on mobile","description":"Users on iOS 17 cannot tap the login button","status":"open","priority":"critical","reporter_id":1}'
run 201 "Low priority issue"                POST "/issues/" \
  '{"id":2,"title":"Typo on footer","description":"Misspelled word","status":"closed","priority":"low","reporter_id":1}'
run 201 "High priority issue (base class)"  POST "/issues/" \
  '{"id":3,"title":"Slow dashboard","description":"Takes 10s to load","status":"open","priority":"high","reporter_id":2}'
run 201 "Medium priority issue (base class)" POST "/issues/" \
  '{"id":4,"title":"Wrong tooltip","description":"Shows old text","status":"in_progress","priority":"medium","reporter_id":2}'
run 201 "Resolved issue"                    POST "/issues/" \
  '{"id":5,"title":"Old crash","description":"Fixed","status":"resolved","priority":"high","reporter_id":1}'

# ---------------------------------------------------------------
section "5. Issues - create (failures)"
run 400 "Empty title"                       POST "/issues/" \
  '{"id":6,"title":"","description":"x","status":"open","priority":"high","reporter_id":1}'
run 400 "Invalid status"                    POST "/issues/" \
  '{"id":6,"title":"t","description":"x","status":"bad","priority":"high","reporter_id":1}'
run 400 "Invalid priority"                  POST "/issues/" \
  '{"id":6,"title":"t","description":"x","status":"open","priority":"urgent","reporter_id":1}'
run 404 "Reporter does not exist"           POST "/issues/" \
  '{"id":6,"title":"t","description":"x","status":"open","priority":"high","reporter_id":99}'
run 400 "Issue with non-integer id"         POST "/issues/" \
  '{"id":"abc","title":"t","description":"x","status":"open","priority":"high","reporter_id":1}'
run 400 "Issue with non-integer reporter_id" POST "/issues/" \
  '{"id":6,"title":"t","description":"x","status":"open","priority":"high","reporter_id":"abc"}'
run 400 "Missing fields"                    POST "/issues/" \
  '{"id":6,"title":"t"}'
run 400 "Duplicate id"                      POST "/issues/" \
  '{"id":1,"title":"Dup","description":"x","status":"open","priority":"high","reporter_id":1}'
run 400 "Invalid JSON body"                 POST "/issues/" 'not json'

# ---------------------------------------------------------------
section "6. Issues - read"
run 200 "List all issues (5 expected)"      GET "/issues/"
run 200 "Issue by id (1)"                   GET "/issues/?id=1"
run 404 "Issue by id, not found"            GET "/issues/?id=99"
run 400 "Issue by non-numeric id"           GET "/issues/?id=abc"
run 200 "Filter status=open (issues 1, 3)"  GET "/issues/?status=open"
run 200 "Filter status=closed (issue 2)"    GET "/issues/?status=closed"
run 200 "Filter status=in_progress (issue 4)" GET "/issues/?status=in_progress"
run 200 "Filter status=resolved (issue 5)"  GET "/issues/?status=resolved"
run 404 "Filter is case-sensitive (Open -> no match)" GET "/issues/?status=Open"
run 404 "Filter with no matches"            GET "/issues/?status=nothing"
run 405 "Wrong method on issues"            DELETE "/issues/"

# ---------------------------------------------------------------
echo "=================== Summary ==================="
echo "Passed: $PASS   Failed: $FAIL"
[[ $FAIL -eq 0 ]]
