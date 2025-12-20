#!/bin/bash
# Test runner script for FoundationChat system tests

set -e

echo "🧪 FoundationChat System Test Suite"
echo "===================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test categories
TESTS=(
    "SystemIntegrationTests"
    "MultiAgentContextualModeTests"
    "MultiAgentScenarioTests"
    "AgentRegistryTests"
    "AgentTests"
    "OrchestrationPatternTests"
    "ToolProtocolConformanceTests"
    "ToolTrackingIntegrationTests"
    "DuckDuckGoToolIntegrationTests"
    "DuckDuckGoNormalizationVerification"
    "DuckDuckGoToolUsageAnalysis"
    "DuckDuckGoTests"
    "DuckDuckGoIntegrationTests"
)

# Function to run a test suite
run_test_suite() {
    local test_name=$1
    echo -e "${YELLOW}Running: ${test_name}${NC}"
    echo "----------------------------------------"
    
    if swift test --filter "$test_name" 2>&1 | tee "/tmp/test_${test_name}.log"; then
        echo -e "${GREEN}✓ ${test_name} passed${NC}"
        echo ""
        return 0
    else
        echo -e "${RED}✗ ${test_name} failed${NC}"
        echo ""
        return 1
    fi
}

# Function to run all tests
run_all_tests() {
    local failed=0
    local passed=0
    
    for test in "${TESTS[@]}"; do
        if run_test_suite "$test"; then
            ((passed++))
        else
            ((failed++))
        fi
    done
    
    echo "===================================="
    echo "Test Summary:"
    echo -e "${GREEN}Passed: ${passed}${NC}"
    if [ $failed -gt 0 ]; then
        echo -e "${RED}Failed: ${failed}${NC}"
    fi
    echo "===================================="
    
    return $failed
}

# Function to run specific test category
run_specific_test() {
    local test_name=$1
    run_test_suite "$test_name"
}

# Main execution
case "${1:-all}" in
    all)
        run_all_tests
        ;;
    integration)
        run_test_suite "SystemIntegrationTests"
        run_test_suite "MultiAgentContextualModeTests"
        run_test_suite "MultiAgentScenarioTests"
        ;;
    scenarios)
        run_test_suite "MultiAgentScenarioTests"
        ;;
    agents)
        run_test_suite "AgentRegistryTests"
        run_test_suite "AgentTests"
        ;;
    orchestration)
        run_test_suite "OrchestrationPatternTests"
        ;;
    tools)
        run_test_suite "ToolProtocolConformanceTests"
        run_test_suite "ToolTrackingIntegrationTests"
        run_test_suite "DuckDuckGoToolIntegrationTests"
        ;;
    duckduckgo)
        run_test_suite "DuckDuckGoTests"
        run_test_suite "DuckDuckGoIntegrationTests"
        run_test_suite "DuckDuckGoNormalizationVerification"
        run_test_suite "DuckDuckGoToolUsageAnalysis"
        ;;
    *)
        if [ -n "$1" ]; then
            run_specific_test "$1"
        else
            echo "Usage: $0 [all|integration|agents|orchestration|tools|duckduckgo|<test_name>]"
            exit 1
        fi
        ;;
esac

exit $?

