#!/bin/bash
# deploy_agent.sh - deploy, run and archive the Attendance Tracker
# Usage: ./deploy_agent.sh [--deploy | --run | --archive | --help]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES="$SCRIPT_DIR/templates"
PROJECT_NAME=""
PROJECT_DIR=""

die() { echo "ERROR: $*" >&2; exit 1; }

ask_project_name() {
    while true; do
        read -r -p "Enter project name: " PROJECT_NAME
        [[ "$PROJECT_NAME" =~ ^[A-Za-z0-9_-]+$ ]] && return
        echo "Use letters, digits, '_' or '-' only."
    done
}

ask_number() {
    while true; do
        read -r -p "$1" REPLY_NUM
        if [[ "$REPLY_NUM" =~ ^[0-9]+$ ]] && (( REPLY_NUM >= $2 && REPLY_NUM <= $3 )); then
            return
        fi
        echo "Enter a whole number between $2 and $3."
    done
}


on_interrupt() {
    echo
    echo "!! Deployment interrupted."
    cd "$SCRIPT_DIR" || exit 1
    if [[ -n "$PROJECT_DIR" && -d "$PROJECT_DIR" ]]; then
        base="$(basename "$PROJECT_DIR")"
        echo "Archiving incomplete project into ${base}_archive.zip ..."
        if zip -rq "${base}_archive.zip" "$base"; then
            rm -rf "$PROJECT_DIR"
            echo "Archive created."
        fi
    else
        echo "Nothing created yet, nothing to archive."
    fi
    echo "Session closed cleanly."
    exit 130
}


deploy() {
    trap on_interrupt SIGINT SIGTSTP

    local missing=0
    for cmd in python3 zip; do
        if command -v "$cmd" >/dev/null 2>&1; then
            echo "  [ok] $cmd"
        else
            echo "  [missing] $cmd" >&2; missing=1
        fi
    done
    (( missing )) && die "Install the missing tool(s) first."
    for f in attendance_checker.py assets.csv config.json; do
        [[ -f "$TEMPLATES/$f" ]] || die "templates/$f not found."
    done

    ask_project_name
    local target="$SCRIPT_DIR/attendance_tracker_${PROJECT_NAME}"
    if [[ -e "$target" ]]; then
        read -r -p "'$target' exists. Overwrite? (y/N): " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then rm -rf "$target"; else die "Aborted: already exists."; fi
    fi
    mkdir -p "$target/Helpers" "$target/reports" || die "Could not create folders."
    PROJECT_DIR="$target"
    echo "Created $PROJECT_DIR"

    cp "$TEMPLATES/attendance_checker.py" "$PROJECT_DIR/"
    cp "$TEMPLATES/config.json" "$PROJECT_DIR/Helpers/"

    echo "Roster: A) copy from template   B) generate fresh"
    while true; do
        read -r -p "Choose A or B: " choice
        [[ "$choice" =~ ^[AaBb]$ ]] && break
    done

    if [[ "$choice" =~ ^[Aa]$ ]]; then
        available=$(( $(wc -l < "$TEMPLATES/assets.csv") - 1 ))
        ask_number "How many students (1-$available)? " 1 "$available"
        head -n $(( REPLY_NUM + 1 )) "$TEMPLATES/assets.csv" > "$PROJECT_DIR/Helpers/assets.csv"
    else
        first=(Alice Bob Carol David Eve Frank Grace Henry Irene Jack Karen Liam Mia Noah Olivia Paul Quinn Rita Sam Tina)
        last=(Johnson Smith Brown Davis Wilson Moore Taylor Clark Lewis Walker Hall Young King Wright Scott Green Baker Adams Nelson Hill)
        ask_number "How many students (1-${#first[@]})? " 1 "${#first[@]}"
        {
            echo "Email,Names,Attendance Count,Absence Count"
            for (( i=0; i<REPLY_NUM; i++ )); do
                f="${first[$i]}"; l="${last[$i]}"
                echo "$(echo "$f" | tr 'A-Z' 'a-z')@example.com,$f $l,0,0"
            done
        } > "$PROJECT_DIR/Helpers/assets.csv"
        sed -i.bak -E 's/("total_sessions": )[0-9]+/\11/' "$PROJECT_DIR/Helpers/config.json"
        rm -f "$PROJECT_DIR/Helpers/config.json.bak"
    fi

    chmod +x "$PROJECT_DIR/attendance_checker.py"
    chmod 600 "$PROJECT_DIR/Helpers/config.json"
    echo "Permissions set:"
    ls -l "$PROJECT_DIR/attendance_checker.py" "$PROJECT_DIR/Helpers/config.json"

    read -r -p "Update alert thresholds? (y/N): " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        read -r -p "New warning [75]: " warn; warn=${warn:-75}
        read -r -p "New failure [50]: " fail; fail=${fail:-50}
        if [[ "$warn" =~ ^[0-9]+$ && "$fail" =~ ^[0-9]+$ ]]; then
            sed -i.bak -E \
                -e "s/(\"warning\": )[0-9]+/\1${warn}/" \
                -e "s/(\"failure\": )[0-9]+/\1${fail}/" \
                "$PROJECT_DIR/Helpers/config.json"
            rm -f "$PROJECT_DIR/Helpers/config.json.bak"
            echo "Thresholds updated."
        else
            echo "Not numbers - keeping defaults."
        fi
    fi

    trap - SIGINT SIGTSTP

    echo "== Verifying: launching the application =="
    run_app
}


select_existing_project() {
    [[ -n "$PROJECT_NAME" ]] || ask_project_name
    PROJECT_DIR="$SCRIPT_DIR/attendance_tracker_${PROJECT_NAME}"
    [[ -d "$PROJECT_DIR" ]] || die "Project does not exist. Deploy it first."
}

run_app() {
    [[ -n "$PROJECT_DIR" ]] || select_existing_project
    ( cd "$PROJECT_DIR" && python3 attendance_checker.py )
}

archive_logs() {
    select_existing_project
    local ts archived=0
    ts="$(date +%Y%m%d_%H%M%S)"
    for name in attendance absent; do
        src="$PROJECT_DIR/reports/${name}.log"
        dest="$PROJECT_DIR/archives/${name}"
        if [[ -f "$src" ]]; then
            mkdir -p "$dest"
            mv "$src" "$dest/${name}_${ts}.log"
            echo "Archived: $dest/${name}_${ts}.log"
            archived=1
        else
            echo "Skipped: reports/${name}.log does not exist."
        fi
    done
    (( archived )) || echo "No logs were archived."
}

usage() {
    echo "Usage: $0 [--deploy | --run | --archive | --help]"
}

case "${1:-}" in
    --deploy)  deploy ;;
    --run)     run_app ;;
    --archive) archive_logs ;;
    --help|-h) usage ;;
    "")
        while true; do
            echo
            echo "1) Deploy  2) Run  3) Archive logs  4) Quit"
            read -r -p "Choice: " opt
            case "$opt" in
                1) deploy ;;
                2) run_app ;;
                3) archive_logs ;;
                4) echo "Bye."; exit 0 ;;
                *) echo "Invalid choice." ;;
            esac
        done ;;
    *) usage; exit 1 ;;
esac
