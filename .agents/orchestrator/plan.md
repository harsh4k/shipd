# Plan — Fix shipd commits issue

## Objective
Diagnose and resolve the issue where commits are no longer displayed on the shipd dashboard when run via PowerShell and CMD.

## Steps
1. **Milestone 1: Exploration and Diagnosis**
   - Dispatch `teamwork_preview_explorer` to analyze how CMD support was added, how commits are retrieved, and why they fail to display.
   - Deliverable: Handoff report with diagnostic findings and a recommended fix strategy.
   - Verification: Reviewer/Orchestrator approves the explorer's strategy.

2. **Milestone 2: Implementation & Code Fix**
   - Dispatch `teamwork_preview_worker` to implement the diagnosed fix.
   - Ensure the fix allows correct retrieval and display under both PowerShell and CMD wrapper (`shipd.cmd`).
   - Run the existing test suite `test_shipd.ps1` to verify.
   - Deliverable: Modified files and verification logs.

3. **Milestone 3: Review & Final Verification**
   - Dispatch `teamwork_preview_reviewer` to review the code changes.
   - Dispatch `teamwork_preview_challenger` to test edge cases.
   - Dispatch `teamwork_preview_auditor` to perform integrity forensics.
   - Deliverable: Clean audit report and approved review.
