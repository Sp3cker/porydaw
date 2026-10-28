"""Cancellation and reap policy for harness-owned process groups."""

import os
import signal
import subprocess
from contextlib import contextmanager


@contextmanager
def cancel_on_signals():
    previous = {}
    interrupted = False

    def interrupt(_signal, _frame):
        nonlocal interrupted
        if not interrupted:
            interrupted = True
            raise KeyboardInterrupt

    try:
        if os.name == "posix":
            for number in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
                previous[number] = signal.signal(number, interrupt)
        yield
    finally:
        for number, handler in previous.items():
            signal.signal(number, handler)


def signal_child(child: subprocess.Popen, *, force: bool = False) -> None:
    try:
        if os.name == "posix":
            os.killpg(child.pid, signal.SIGKILL if force else signal.SIGTERM)
        elif force:
            child.kill()
        else:
            child.terminate()
    except ProcessLookupError:
        pass


def stop_child(child: subprocess.Popen, grace: float = 0.5) -> None:
    if child.poll() is None:
        signal_child(child)
        try:
            child.wait(timeout=grace)
        except subprocess.TimeoutExpired:
            signal_child(child, force=True)
    if os.name == "posix":
        signal_child(child, force=True)
    child.wait()
