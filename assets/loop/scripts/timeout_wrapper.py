import os
import selectors
import signal
import subprocess
import sys
import time


def terminate_process_group(
    proc: subprocess.Popen[bytes], grace_seconds: int = 5
) -> None:
    """Terminate process group with TERM grace, then KILL if still alive."""
    if proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except Exception:
        return

    deadline = time.time() + max(0, grace_seconds)
    while time.time() < deadline:
        if proc.poll() is not None:
            return
        time.sleep(0.1)

    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except Exception:
        return


def main():
    if len(sys.argv) < 3:
        print(
            "Usage: timeout_wrapper.py <timeout_seconds> <command> [no_output_timeout_seconds]"
        )
        sys.exit(1)

    timeout_s = int(sys.argv[1])
    cmd = sys.argv[2]
    no_output_timeout_s = int(sys.argv[3]) if len(sys.argv) >= 4 else 0
    start_time = time.time()
    last_output_time = start_time

    # Use preexec_fn=os.setsid to create a process group
    proc = subprocess.Popen(
        ["bash", "-lc", cmd],
        stdin=sys.stdin,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        preexec_fn=os.setsid,
        bufsize=0,
    )

    # Set non-blocking mode on stdout for incremental streaming.
    import fcntl

    fd = proc.stdout.fileno()
    fl = fcntl.fcntl(fd, fcntl.F_GETFL)
    fcntl.fcntl(fd, fcntl.F_SETFL, fl | os.O_NONBLOCK)
    selector = selectors.DefaultSelector()
    selector.register(fd, selectors.EVENT_READ)

    try:
        eof = False
        while True:
            # Check for timeout
            if (time.time() - start_time) > timeout_s:
                terminate_process_group(proc)
                print("\nTIMEOUT")
                sys.exit(124)

            # Wait briefly for readable stdout.
            events = selector.select(timeout=0.1)
            for key, _ in events:
                try:
                    chunk = os.read(key.fd, 4096)
                except BlockingIOError:
                    continue
                if chunk:
                    last_output_time = time.time()
                    sys.stdout.write(chunk.decode("utf-8", errors="ignore"))
                    sys.stdout.flush()
                else:
                    eof = True
                    try:
                        selector.unregister(key.fd)
                    except Exception:
                        pass

            # Optional silent-output watchdog: fail fast if agent emits nothing.
            if (
                no_output_timeout_s > 0
                and (time.time() - last_output_time) > no_output_timeout_s
            ):
                terminate_process_group(proc)
                print("\nNO_OUTPUT_TIMEOUT")
                sys.exit(125)

            # If process is done and stream reached EOF, exit.
            if proc.poll() is not None and eof:
                break

        # Exit with the wrapped command's return code.
        # Note: avoid catching SystemExit so a normal completion isn't
        # converted into a non-zero exit by the generic handler below.
        sys.exit(proc.returncode)

    except KeyboardInterrupt:
        terminate_process_group(proc, grace_seconds=1)
        sys.exit(1)
    except Exception as e:
        terminate_process_group(proc, grace_seconds=1)
        print(f"\nWRAPPER_ERROR: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
