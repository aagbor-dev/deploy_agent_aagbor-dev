# Attendance Tracker Deploy Agent
 
`deploy_agent.sh` is a shell script that deploys, runs and archives the logs of the Student Attendance Tracker (`attendance_checker.py`, which is never modified). It also handles Ctrl+C and Ctrl+Z safely during deployment.
 
## Folder layout
 
```
deploy_agent_aagbor-dev/
├── deploy_agent.sh
├── README.md
└── templates/
    ├── attendance_checker.py
    ├── assets.csv
    └── config.json
```
 
## How to run and choose a feature
 
First make the script executable (once):
 
```bash
chmod +x deploy_agent.sh
```
 
I chose **command-line flags**, plus an **interactive menu** when no flag is given:
 
| Command | Feature |
|---|---|
| `./deploy_agent.sh --deploy` | Feature 1: deploy (and then run to verify) |
| `./deploy_agent.sh --run` | Feature 2: run an already deployed project |
| `./deploy_agent.sh --archive` | Feature 3: archive the logs |
| `./deploy_agent.sh` | Menu with all three features |
| `./deploy_agent.sh --help` | Show usage |
 
`--run` and `--archive` ask for the project name (just the `{input}` part, e.g. `demo` for `attendance_tracker_demo`).
 
## Feature 1: Deploy
 
1. Pre-flight checks that `python3` and `zip` are installed (and that the three files exist in `templates/`). It stops early with a clear message if anything is missing.
2. Asks for a project name and creates `attendance_tracker_{input}/` with `Helpers/` and `reports/`. If the directory already exists, it asks whether to overwrite, otherwise it aborts.
3. Copies `attendance_checker.py` and `config.json` unmodified from `templates/`. For the roster, the user chooses:
   - **Option A:** copy N students (plus the header) from `templates/assets.csv`.
   - **Option B:** generate N students from sample name arrays in the script, with Attendance Count and Absence Count both `0`.
4. Sets permissions: `chmod +x` on `attendance_checker.py` and `chmod 600` on `Helpers/config.json`, then prints them with `ls -l`.
5. Offers to update the alert thresholds (see below).
6. Verifies the deployment by running the application.
 
### Why `total_sessions` is 5 or 1
 
`total_sessions` must always be one more than the prior sessions recorded in the roster.
- Option A: template students have 4 prior sessions, so `total_sessions` stays **5**.
- Option B: a fresh roster has 0 prior sessions, so the script sets `total_sessions` to **1** using `sed`.
 
No prompt is needed for this because the correct value follows from the roster choice.
 
Note: the application does not update `total_sessions` itself. If the same project is run a second time, the app prints a note that students have more prior sessions than expected, but it still proceeds.
 
## How the threshold update works
 
The script asks "Update alert thresholds? (y/N)". If yes, it reads new values for `warning` (default 75) and `failure` (default 50) with `read`, checks they are numbers, then edits the deployed `config.json` in place with `sed`, targeting only the `"warning": <number>` and `"failure": <number>` lines. The rest of the file is not reformatted or reordered. If the input is not numeric, the defaults are kept.
 
## How log archiving works
 
After a run, `--archive` checks whether `reports/attendance.log` and `reports/absent.log` exist. Each existing log is moved into its own directory with a timestamp in the name:
 
```
attendance_tracker_{input}/archives/
├── attendance/attendance_YYYYMMDD_HHMMSS.log
└── absent/absent_YYYYMMDD_HHMMSS.log
```
 
The script prints the final path of each archived log. If a log does not exist (for example nobody was absent so there is no `absent.log`, or the logs were already archived), it prints a "Skipped" message and continues without crashing.
 
## Ctrl+C / Ctrl+Z handling
 
During deployment the script traps `SIGINT` (Ctrl+C) and `SIGTSTP` (Ctrl+Z). On either signal it:
1. prints a message that the deployment was interrupted,
2. uses the `zip` command to archive whatever exists of `attendance_tracker_{input}/` into `attendance_tracker_{input}_archive.zip`,
3. removes the half-made project directory,
4. exits cleanly.
 
The trap is turned off once deployment finishes, so it does not affect `attendance_checker.py` while a marking session is running.
 
### How to test it
 
1. Run `./deploy_agent.sh --deploy`.
2. Enter a project name (e.g. `sigtest`).
3. At the `Choose A or B:` prompt, press **Ctrl+C** (repeat with another name and **Ctrl+Z**).
4. Run `ls` to confirm `attendance_tracker_sigtest_archive.zip` exists and the `attendance_tracker_sigtest` folder is gone.
5. Run `unzip -l attendance_tracker_sigtest_archive.zip` to see the contents.
 
### What the .zip contains
 
Only what had been created at the moment of the interrupt. When interrupted at the roster prompt, it contains `attendance_tracker_sigtest/`, `Helpers/`, `Helpers/config.json`, `reports/` and `attendance_checker.py` (5 entries). `assets.csv` is not there because the roster step had not happened yet. If interrupted before the folder is created, there is nothing to archive and the script says so.
 
## How I tested the deployed structure
 
- `ls -R attendance_tracker_demo` to confirm `attendance_checker.py`, `Helpers/assets.csv`, `Helpers/config.json` and `reports/` exist.
- `ls -l` (printed by the script) to confirm `attendance_checker.py` is executable and `config.json` is `-rw-------`.
- Ran a live marking session (present and absent) and confirmed `reports/attendance.log` and `reports/absent.log` were created.
- Ran `--archive` and checked the timestamped files with `ls -R archives`, then ran it again to confirm the "does not exist" case is handled.
- Tested Ctrl+C and Ctrl+Z as described above.

