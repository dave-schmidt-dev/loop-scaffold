.PHONY: check check-bash check-python check-layout

SHELL_FILES := \
	assets/loop/agent.sh \
	assets/loop/auditor.sh \
	assets/loop/ralph.sh \
	assets/loop/reviewer.sh \
	scripts/init_spec_scaffold.sh \
	scripts/install_loop.sh \
	assets/loop/scripts/agent_dispatcher.sh \
	assets/loop/scripts/automate_next.sh \
	assets/loop/scripts/checkpoint_exec_lib.sh \
	assets/loop/scripts/colorize_loop_output.sh \
	assets/loop/scripts/exit_codes.sh \
	assets/loop/scripts/loop_process_scan.sh \
	assets/loop/scripts/metrics_lib.sh \
	assets/loop/scripts/prune_loop_logs.sh \
	assets/loop/scripts/run_all_tasks.sh \
	assets/loop/scripts/run_audit_exec.sh \
	assets/loop/scripts/run_next_task.sh \
	assets/loop/scripts/run_review_exec.sh \
	assets/loop/scripts/stop_loop_gracefully.sh

PYTHON_FILES := \
	assets/guard/spec_guard.py \
	assets/loop/scripts/extract_findings.py \
	assets/loop/scripts/loop_checklist.py \
	assets/loop/scripts/loop_report.py \
	assets/loop/scripts/loop_status.py \
	assets/loop/scripts/process_findings.py \
	assets/loop/scripts/timeout_wrapper.py

check: check-layout check-bash check-python

check-layout:
	test -f SKILL.md
	test -f agents/openai.yaml
	test -f scripts/init_spec_scaffold.sh
	test -f scripts/install_loop.sh
	test -f assets/guard/spec_guard.py
	test -f assets/loop/PROMPT.md
	test -f assets/loop/REVIEW_PROMPT.md
	test -f assets/loop/AUDIT_PROMPT.md
	test -f assets/loop/ARCH_REVIEW_PROMPT.md

check-bash:
	bash -n $(SHELL_FILES)

check-python:
	python3 -m py_compile $(PYTHON_FILES)
