#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Running system checks...${NC}\n"

# Track test results
PASS_COUNT=0
FAIL_COUNT=0
TOTAL_CHECKS=0

# Function to check command existence
check_command() {
    local cmd=$1
    local display_name=$2
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    if command -v "$cmd" &> /dev/null; then
        local version=$(${cmd} --version 2>&1 | head -n 1)
        echo -e "${GREEN}✓${NC} ${display_name} found: ${version}"
        PASS_COUNT=$((PASS_COUNT + 1))
        return 0
    else
        echo -e "${RED}✗${NC} ${display_name} not found"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return 1
    fi
}

# Check for development tools
echo -e "${YELLOW}Checking development tools:${NC}"
check_command "cursor" "Cursor"
check_command "code-insiders" "VS Code Insiders"
check_command "git" "Git"
check_command "node" "Node.js"
check_command "npm" "npm"

# Check for shell tools
echo -e "\n${YELLOW}Checking shell tools:${NC}"
check_command "bash" "Bash"
check_command "zsh" "Zsh"

# Check for other useful tools
echo -e "\n${YELLOW}Checking additional tools:${NC}"
check_command "docker" "Docker"
check_command "python3" "Python 3"
check_command "pip3" "pip3"
check_command "curl" "curl"
check_command "wget" "wget"
check_command "jq" "jq"

# Check for build tools
echo -e "\n${YELLOW}Checking build tools:${NC}"
check_command "make" "Make"
check_command "gcc" "GCC"
check_command "g++" "G++"
check_command "cargo" "Rust Cargo"
check_command "go" "Go"

# Check system information
echo -e "\n${YELLOW}System Information:${NC}"
if [ -f /etc/os-release ]; then
    OS_NAME=$(grep "^PRETTY_NAME" /etc/os-release | cut -d'"' -f2)
    echo -e "  OS: ${OS_NAME}"
else
    echo -e "  OS: $(uname -s) $(uname -r)"
fi
echo -e "  Architecture: $(uname -m)"
echo -e "  Hostname: $(hostname)"
echo -e "  Shell: ${SHELL}"
echo -e "  User: ${USER}"

# Check disk space
echo -e "\n${YELLOW}Disk Space:${NC}"
df -h / | tail -n 1 | awk '{print "  Root: "$3" used / "$2" total ("$5" used)"}'
if [ -d "$HOME" ]; then
    df -h "$HOME" | tail -n 1 | awk '{print "  Home: "$3" used / "$2" total ("$5" used)"}'
fi

# Check memory
echo -e "\n${YELLOW}Memory:${NC}"
if command -v free &> /dev/null; then
    free -h | grep "^Mem:" | awk '{print "  Total: "$2"  Used: "$3"  Free: "$4}'
fi

# Summary
echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}Test Summary:${NC}"
echo -e "  Total checks: ${TOTAL_CHECKS}"
echo -e "  ${GREEN}Passed: ${PASS_COUNT}${NC}"
echo -e "  ${RED}Failed: ${FAIL_COUNT}${NC}"
echo -e "${BLUE}========================================${NC}"

# Exit with appropriate code
if [ $FAIL_COUNT -gt 0 ]; then
    echo -e "\n${YELLOW}Some tools are missing. Install them to improve your development environment.${NC}"
    exit 1
else
    echo -e "\n${GREEN}All checks passed!${NC}"
    exit 0
fi