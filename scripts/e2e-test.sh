#!/usr/bin/env bash
# End-to-End multi-language verification suite for Online Code Sandbox.
# Usage: ./scripts/e2e-test.sh [API_URL]
set -euo pipefail

API_URL="${1:-http://localhost:3000}"
PASSED=0
FAILED=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Starting E2E Integration Suite ===${NC}"
echo "Target API: $API_URL"

# ── 1. Wait for API Healthcheck ───────────────────────────────────────────────
echo -n "Waiting for API to become healthy..."
MAX_HEALTH_ATTEMPTS=30
HEALTH_OK=false

for i in $(seq 1 "$MAX_HEALTH_ATTEMPTS"); do
  HEALTH_RESP=$(curl -s --connect-timeout 2 "$API_URL/api/health" 2>/dev/null || echo "")
  if echo "$HEALTH_RESP" | grep -q '"status":"ok"'; then
    HEALTH_OK=true
    echo -e " ${GREEN}OK${NC} (attempt $i)"
    break
  fi
  echo -n "."
  sleep 1
done

if [ "$HEALTH_OK" != "true" ]; then
  echo -e "\n${RED}Error: API failed to report healthy status within ${MAX_HEALTH_ATTEMPTS}s.${NC}"
  exit 1
fi

# Helper to run a test execution
run_test() {
  local test_name="$1"
  local language="$2"
  local code="$3"
  local expected_status="$4"
  local expected_output_substr="${5:-}"

  echo -e "\n${BLUE}▶ Testing:${NC} $test_name ($language)"

  # Submit job
  local payload
  payload=$(node -e '
    const [, lang, src] = process.argv;
    console.log(JSON.stringify({ language: lang, source: src }));
  ' "$language" "$code")

  local submit_resp
  submit_resp=$(curl -s -X POST "$API_URL/api/executions" \
    -H "Content-Type: application/json" \
    -d "$payload")

  local execution_id
  execution_id=$(node -e '
    try {
      const resp = JSON.parse(process.argv[1]);
      console.log(resp.executionId || "");
    } catch {
      console.log("");
    }
  ' "$submit_resp")

  if [ -z "$execution_id" ]; then
    echo -e "${RED}[FAIL]${NC} Failed to submit execution. Response: $submit_resp"
    FAILED=$((FAILED + 1))
    return
  fi

  echo "  Execution ID: $execution_id"

  # Poll until terminal status
  local final_resp=""
  local final_status=""
  local attempts=0
  local max_attempts=40

  while [ $attempts -lt $max_attempts ]; do
    final_resp=$(curl -s "$API_URL/api/executions/$execution_id")
    final_status=$(node -e '
      try {
        const resp = JSON.parse(process.argv[1]);
        console.log(resp.status || "");
      } catch {
        console.log("");
      }
    ' "$final_resp")

    if [[ "$final_status" =~ ^(COMPLETED|TIMEOUT|RUNTIME_ERROR|OUTPUT_LIMIT|CANCELLED)$ ]]; then
      break
    fi

    attempts=$((attempts + 1))
    sleep 0.5
  done

  # Verify status
  if [ "$final_status" != "$expected_status" ]; then
    echo -e "${RED}[FAIL]${NC} Expected status '$expected_status', got '$final_status'."
    echo "  Payload response: $final_resp"
    FAILED=$((FAILED + 1))
    return
  fi

  # Verify expected output substring if requested
  if [ -n "$expected_output_substr" ]; then
    local stdout_content
    stdout_content=$(node -e '
      try {
        const resp = JSON.parse(process.argv[1]);
        console.log((resp.output || "") + "\n" + (resp.error || ""));
      } catch {
        console.log("");
      }
    ' "$final_resp")

    if ! echo "$stdout_content" | grep -q "$expected_output_substr"; then
      echo -e "${RED}[FAIL]${NC} Expected output to contain '$expected_output_substr'."
      echo "  Actual output: $stdout_content"
      FAILED=$((FAILED + 1))
      return
    fi
  fi

  echo -e "${GREEN}[PASS]${NC} Status: $final_status"
  PASSED=$((PASSED + 1))
}

# ── 2. Language Execution Tests ──────────────────────────────────────────────

# Python
run_test "Python Basic Print" "python" \
  'print("e2e-python-success")' \
  "COMPLETED" "e2e-python-success"

# JavaScript
run_test "JavaScript Basic Console" "javascript" \
  'console.log("e2e-javascript-success");' \
  "COMPLETED" "e2e-javascript-success"

# C++
run_test "C++ std::cout" "cpp" \
  '#include <iostream>
int main() {
    std::cout << "e2e-cpp-success" << std::endl;
    return 0;
}' \
  "COMPLETED" "e2e-cpp-success"

# C
run_test "C printf" "c" \
  '#include <stdio.h>
int main() {
    printf("e2e-c-success\n");
    return 0;
}' \
  "COMPLETED" "e2e-c-success"

# Java
run_test "Java System.out" "java" \
  'public class Main {
    public static void main(String[] args) {
        System.out.println("e2e-java-success");
    }
}' \
  "COMPLETED" "e2e-java-success"

# Runtime Error Handling
run_test "Python ZeroDivisionError" "python" \
  'x = 1 / 0' \
  "RUNTIME_ERROR" "ZeroDivisionError"

# ── 3. Summary ───────────────────────────────────────────────────────────────
echo -e "\n${BLUE}=== E2E Test Suite Summary ===${NC}"
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"

if [ $FAILED -gt 0 ]; then
  echo -e "${RED}E2E verification FAILED!${NC}"
  exit 1
fi

echo -e "${GREEN}All E2E verification tests PASSED successfully!${NC}"
exit 0
