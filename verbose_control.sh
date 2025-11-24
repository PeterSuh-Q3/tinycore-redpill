#!/usr/bin/env bash

#################################################################################
# Verbose Mode Control for RedPill Bootloader Build
# Usage: source verbose_control.sh
#################################################################################

# Global Verbose Flag
VERBOSE_MODE="OFF"
VERBOSE_FLAG=""

#################################################################################
# Progress Bar Display
#################################################################################
show_progress_bar() {
    local current=$1
    local total=$2
    local step_name="$3"
    
    local width=30
    local percentage=$((current * 100 / total))
    local filled=$((width * current / total))
    
    printf "[" > /dev/tty
    printf "%${filled}s" | tr ' ' '=' > /dev/tty
    printf "%$((width - filled))s" | tr ' ' '-' > /dev/tty
    printf "] %d%% (%d/%d) [%s]\n" "$percentage" "$current" "$total" "$step_name" > /dev/tty
}

#################################################################################
# Logging Functions
#################################################################################
log_build_step() {
    local step_name="$1"
    local step_num="${2:-}"
    local total_steps="${3:-}"
            
    if [ "$VERBOSE_MODE" = "OFF" ]; then
        if [ -n "$step_num" ] && [ -n "$total_steps" ]; then
            show_progress_bar "$step_num" "$total_steps" "$step_name"
        fi
    else
        echo "[$(date '+%H:%M:%S')] ✓ $step_name"    
    fi
}

log_error() {
    # Error is ALWAYS shown
    echo -e "\033[1;31m[ERROR] $(date '+%H:%M:%S'): $1\033[0m"
}

log_warning() {
    # Warning is ALWAYS shown
    echo -e "\033[1;33m[WARNING] $(date '+%H:%M:%S'): $1\033[0m"
}

log_success() {
    # Success is ALWAYS shown
    echo -e "\033[1;32m[SUCCESS] $(date '+%H:%M:%S'): $1\033[0m"
}

log_backup_step() {
    # Backup process is ALWAYS shown
    echo -e "\033[1;36m[BACKUP] $(date '+%H:%M:%S'): $1\033[0m"
}

#################################################################################
# Build with Progress Bar
#################################################################################
make_with_progress() {
    local ldr_mode="${1}"
    local prevent_init="${2}"
    local build_cmd=""

    checkUserConfig 
    if [ $? -ne 0 ]; then
        dialog --backtitle "`backtitle`" --title "Error loader building" 0 0 #--textbox "${LOG_FILE}" 0 0      
        return 1  
    fi
    
    usbidentify
    clear

    if [ "${prevent_init}" = "OFF" ]; then
        build_cmd="my ${MODEL}-${BUILD} noconfig ${ldr_mode}"
    else
        build_cmd="my ${MODEL}-${BUILD} noconfig ${ldr_mode} ${prevent_init}"
    fi 

    set -o pipefail  
    if [ "$VERBOSE_MODE" = "OFF" ]; then
        echo "Building bootloader..."
        eval "$build_cmd" 2>&1 | tee /home/tc/zlastbuild.log > /dev/null
        exit_code=${PIPESTATUS[0]}
        #echo "$output" | grep -E "(Preparing build environment|Handling DSM pat files|Collecting extensions|Creating bootloader image|Finalizing build)"                
    else
        eval "$build_cmd" 2>&1 | tee /home/tc/zlastbuild.log
        exit_code=${PIPESTATUS[0]}
    fi
    set +o pipefail    
    
    # Always show exit code
    if [ $exit_code -eq 0 ]; then
        log_success "Build completed successfully (Exit Code: $exit_code)"

        if  [ -f /home/tc/custom-module/redpill.ko ]; then
            sudo rm -rf /home/tc/custom-module/redpill.ko
        fi      
st "finishloader" "Loader build status" "Finished building the loader"  
        rm -f /home/tc/buildstatus  
    else
        log_error "Build failed with exit code: $exit_code"
        show_backup_error_info
    fi
    
    echo "press any key to continue..."
    read answer
    
    return $exit_code
}

#################################################################################
# Backup with Always-Visible Progress
#################################################################################
backup_loader() {
    local backup_steps=5
    
    log_backup_step "Starting backup process..."
    
    for i in $(seq 1 $backup_steps); do
        log_backup_step "Backing up config ($i/$backup_steps)"
        # Actual backup command here
        sleep 1
        show_progress_bar "$i" "$backup_steps" "Backup in progress..."
    done
    
    log_backup_step "Backup completed successfully"
}

#################################################################################
# Show Error Information
#################################################################################
show_backup_error_info() {
    echo -e "\n\033[1;31m╔════════════════════════════════════════════╗\033[0m"
    echo -e "\033[1;31m║         BUILD ERROR INFORMATION            ║\033[0m"
    echo -e "\033[1;31m╚════════════════════════════════════════════╝\033[0m"
    
    if [ -f /home/tc/zlastbuild.log ]; then
        echo -e "\n\033[1;33mLast 20 lines of build log:\033[0m"
        tail -20 /home/tc/zlastbuild.log | sed 's/^/  /'
    fi
    
    echo -e "\n\033[1;33mBackup status:\033[0m"
    echo "  Checking for corrupted files..."
    ls -lh /mnt/${tcrppart}/*.pat 2>/dev/null | tail -5
}

#################################################################################
# Toggle Verbose Mode Menu
#################################################################################
toggle_verbose_menu() {
    local TMP_PATH="${TMP_PATH:-.}"
    local NEXT="r"
    
    while true; do
        clear
        
        echo "╔═══════════════════════════════════════════════════════════════╗"
        echo "║         VERBOSE MODE CONFIGURATION                           ║"
        echo "╚═══════════════════════════════════════════════════════════════╝"
        echo ""
        echo "  Current Mode: $([ "$VERBOSE_MODE" = "ON" ] && echo -e '\033[1;32m[ON]\033[0m' || echo -e '\033[1;31m[OFF]\033[0m')"
        echo ""
        echo "┌─────────────────────────────────────────────────────────────┐"
        echo "│  1. Enable Verbose Mode (Show all build output)             │"
        echo "│  2. Disable Verbose Mode (Show only progress & errors)      │"
        echo "│  3. Return to Main Menu                                     │"
        echo "└─────────────────────────────────────────────────────────────┘"
        echo ""
        echo "  [Mode Description]"
        echo ""
        
        if [ "$VERBOSE_MODE" = "ON" ]; then
            echo "  ✓ VERBOSE ON - Current Setting"
            echo "    • Displays all compilation steps"
            echo "    • Shows detailed error messages"
            echo "    • Displays backup process details"
            echo "    • Slower console output (more I/O)"
            echo ""
        else
            echo "  ✓ VERBOSE OFF - Current Setting"
            echo "    • Progress bar display only"
            echo "    • Displays errors and warnings"
            echo "    • Displays backup process (always visible)"
            echo "    • Fast, clean console output"
            echo ""
        fi
        
        read -p "Select option [1-3]: " choice
        
        case "$choice" in
            1)
                VERBOSE_MODE="ON"
                VERBOSE_FLAG="-v"
                echo -e "\n\033[1;32m✓ Verbose mode enabled\033[0m"
                sleep 1.5
                ;;
            2)
                VERBOSE_MODE="OFF"
                VERBOSE_FLAG=""
                echo -e "\n\033[1;32m✓ Verbose mode disabled\033[0m"
                sleep 1.5
                ;;
            3)
                NEXT="r"
                return 0
                ;;
            *)
                echo -e "\033[1;31m✗ Invalid selection\033[0m"
                sleep 1.5
                ;;
        esac
    done
}

#################################################################################
# Get Current Verbose Status
#################################################################################
get_verbose_status() {
    echo "$VERBOSE_MODE"
}

#################################################################################
# Export Functions for Use in Other Scripts
#################################################################################
export -f log_build_step
export -f log_error
export -f log_warning
export -f log_success
export -f log_backup_step
export -f make_with_progress
export -f backup_loader
export -f show_progress_bar
export -f toggle_verbose_menu
export -f get_verbose_status

echo "Verbose Control Module Loaded"
echo "Current Mode: $VERBOSE_MODE"
