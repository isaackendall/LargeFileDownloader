#!/usr/bin/env python3
"""Simple macOS GUI for large-file downloads with aria2c."""

from __future__ import annotations

import os
import queue
import shlex
import shutil
import signal
import subprocess
import threading
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path, PurePosixPath

try:
    import tkinter as tk
    from tkinter import filedialog, messagebox, ttk
    from tkinter.scrolledtext import ScrolledText
except ModuleNotFoundError as exc:  # pragma: no cover - environment-specific
    raise SystemExit(
        "tkinter is not available in this Python installation. "
        "Use a Python 3 build for macOS that includes Tk support."
    ) from exc


DEFAULT_CONNECTIONS = 8
DEFAULT_SPLITS = 8
DEFAULT_STATUS = "Ready"
POLL_INTERVAL_MS = 100
MIN_PARALLEL_VALUE = 1
MAX_PARALLEL_VALUE = 32


class RedirectResolver:
    """Resolve redirected URLs using HEAD first, then GET if needed."""

    USER_AGENT = "mac-aria-gui-downloader/1.0"

    @classmethod
    def resolve(cls, url: str) -> str:
        head_error = None

        try:
            return cls._resolve_with_method(url, "HEAD")
        except Exception as exc:  # pragma: no cover - fallback path
            head_error = exc

        try:
            return cls._resolve_with_method(url, "GET")
        except Exception as exc:
            message = f"Unable to resolve redirects for URL.\nHEAD error: {head_error}\nGET error: {exc}"
            raise RuntimeError(message) from exc

    @classmethod
    def _resolve_with_method(cls, url: str, method: str) -> str:
        headers = {"User-Agent": cls.USER_AGENT}
        request = urllib.request.Request(url, headers=headers, method=method)

        with urllib.request.urlopen(request, timeout=30) as response:
            response.read(0)
            return response.geturl()


class DownloaderApp:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title("Aria2 macOS Downloader")
        self.root.minsize(920, 680)

        self.log_queue: queue.Queue[tuple[str, object]] = queue.Queue()
        self.download_thread: threading.Thread | None = None
        self.process: subprocess.Popen[str] | None = None
        self.stop_requested = False
        self.last_folder = str(Path.home() / "Downloads")
        self.filename_autofilled = False
        self._updating_filename = False

        self.url_var = tk.StringVar()
        self.folder_var = tk.StringVar(value=self.last_folder)
        self.filename_var = tk.StringVar()
        self.connections_var = tk.IntVar(value=DEFAULT_CONNECTIONS)
        self.splits_var = tk.IntVar(value=DEFAULT_SPLITS)
        self.resolve_var = tk.BooleanVar(value=False)
        self.keep_awake_var = tk.BooleanVar(value=True)
        self.status_var = tk.StringVar(value=DEFAULT_STATUS)
        self.resolved_url_var = tk.StringVar(value="")
        self.command_var = tk.StringVar(value="")

        self._build_ui()
        self.url_var.trace_add("write", self._on_url_changed)
        self.filename_var.trace_add("write", self._on_filename_changed)
        self.root.after(POLL_INTERVAL_MS, self._process_queue)
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)

    def _build_ui(self) -> None:
        container = ttk.Frame(self.root, padding=12)
        container.pack(fill=tk.BOTH, expand=True)
        container.columnconfigure(1, weight=1)
        container.rowconfigure(6, weight=1)

        ttk.Label(container, text="Download URL").grid(row=0, column=0, sticky="w", pady=(0, 8))
        url_frame = ttk.Frame(container)
        url_frame.grid(row=0, column=1, columnspan=3, sticky="ew", pady=(0, 8))
        url_frame.columnconfigure(0, weight=1)
        ttk.Entry(url_frame, textvariable=self.url_var).grid(row=0, column=0, sticky="ew", padx=(0, 6))
        ttk.Button(url_frame, text="Paste from Clipboard", command=self.paste_from_clipboard).grid(row=0, column=1)

        ttk.Label(container, text="Save Folder").grid(row=1, column=0, sticky="w", pady=(0, 8))
        folder_frame = ttk.Frame(container)
        folder_frame.grid(row=1, column=1, columnspan=3, sticky="ew", pady=(0, 8))
        folder_frame.columnconfigure(0, weight=1)
        ttk.Entry(folder_frame, textvariable=self.folder_var).grid(row=0, column=0, sticky="ew", padx=(0, 6))
        ttk.Button(folder_frame, text="Choose Folder", command=self.choose_folder).grid(row=0, column=1, padx=(0, 6))
        ttk.Button(folder_frame, text="Open Folder", command=self.open_folder).grid(row=0, column=2)

        ttk.Label(container, text="Output Filename").grid(row=2, column=0, sticky="w", pady=(0, 8))
        ttk.Entry(container, textvariable=self.filename_var).grid(row=2, column=1, columnspan=3, sticky="ew", pady=(0, 8))

        ttk.Label(container, text="Connections").grid(row=3, column=0, sticky="w", pady=(0, 8))
        ttk.Spinbox(
            container,
            from_=MIN_PARALLEL_VALUE,
            to=MAX_PARALLEL_VALUE,
            textvariable=self.connections_var,
            width=8,
        ).grid(row=3, column=1, sticky="w", pady=(0, 8))

        ttk.Label(container, text="Splits").grid(row=3, column=2, sticky="w", pady=(0, 8))
        ttk.Spinbox(
            container,
            from_=MIN_PARALLEL_VALUE,
            to=MAX_PARALLEL_VALUE,
            textvariable=self.splits_var,
            width=8,
        ).grid(row=3, column=3, sticky="w", pady=(0, 8))

        options_frame = ttk.Frame(container)
        options_frame.grid(row=4, column=0, columnspan=4, sticky="w", pady=(0, 8))
        ttk.Checkbutton(
            options_frame,
            text="Resolve final URL before download",
            variable=self.resolve_var,
        ).grid(row=0, column=0, sticky="w", padx=(0, 16))
        ttk.Checkbutton(
            options_frame,
            text="Keep Mac awake during download",
            variable=self.keep_awake_var,
        ).grid(row=0, column=1, sticky="w")

        ttk.Label(container, text="Resolved URL").grid(row=5, column=0, sticky="nw", pady=(0, 8))
        resolved_frame = ttk.Frame(container)
        resolved_frame.grid(row=5, column=1, columnspan=3, sticky="ew", pady=(0, 8))
        resolved_frame.columnconfigure(0, weight=1)
        resolved_entry = ttk.Entry(resolved_frame, textvariable=self.resolved_url_var, state="readonly")
        resolved_entry.grid(row=0, column=0, sticky="ew", padx=(0, 6))
        ttk.Button(resolved_frame, text="Copy Resolved URL", command=self.copy_resolved_url).grid(row=0, column=1)

        ttk.Label(container, text="Command").grid(row=6, column=0, sticky="nw")
        command_frame = ttk.Frame(container)
        command_frame.grid(row=6, column=1, columnspan=3, sticky="ew", pady=(0, 8))
        command_frame.columnconfigure(0, weight=1)
        command_entry = ttk.Entry(command_frame, textvariable=self.command_var, state="readonly")
        command_entry.grid(row=0, column=0, sticky="ew", padx=(0, 6))
        ttk.Button(command_frame, text="Copy Command", command=self.copy_command).grid(row=0, column=1)

        status_frame = ttk.Frame(container)
        status_frame.grid(row=7, column=0, columnspan=4, sticky="ew", pady=(0, 8))
        status_frame.columnconfigure(1, weight=1)
        ttk.Label(status_frame, text="Status").grid(row=0, column=0, sticky="w", padx=(0, 8))
        ttk.Label(status_frame, textvariable=self.status_var).grid(row=0, column=1, sticky="w")

        button_frame = ttk.Frame(container)
        button_frame.grid(row=8, column=0, columnspan=4, sticky="w", pady=(0, 8))
        self.start_button = ttk.Button(button_frame, text="Start Download", command=self.start_download)
        self.start_button.grid(row=0, column=0, padx=(0, 6))
        self.stop_button = ttk.Button(button_frame, text="Stop", command=self.stop_download, state=tk.DISABLED)
        self.stop_button.grid(row=0, column=1, padx=(0, 6))
        ttk.Button(button_frame, text="Clear Log", command=self.clear_log).grid(row=0, column=2)

        ttk.Label(container, text="Logs").grid(row=9, column=0, sticky="nw")
        self.log_text = ScrolledText(container, wrap=tk.WORD, height=18, state=tk.DISABLED)
        self.log_text.grid(row=9, column=1, columnspan=3, sticky="nsew")
        container.rowconfigure(9, weight=1)

    def paste_from_clipboard(self) -> None:
        try:
            clipboard_text = self.root.clipboard_get().strip()
        except tk.TclError:
            messagebox.showerror("Clipboard Error", "Clipboard does not contain text.")
            return

        self.url_var.set(clipboard_text)

    def choose_folder(self) -> None:
        initial_dir = self.folder_var.get().strip() or self.last_folder
        selected = filedialog.askdirectory(initialdir=initial_dir or str(Path.home()))
        if selected:
            self.last_folder = selected
            self.folder_var.set(selected)

    def open_folder(self) -> None:
        folder = self.folder_var.get().strip()
        if not folder:
            messagebox.showerror("Folder Error", "Select a folder first.")
            return

        if not os.path.isdir(folder):
            messagebox.showerror("Folder Error", "The selected folder does not exist.")
            return

        try:
            subprocess.Popen(["open", folder])
        except OSError as exc:
            messagebox.showerror("Open Folder Error", f"Unable to open folder:\n{exc}")

    def copy_resolved_url(self) -> None:
        resolved = self.resolved_url_var.get().strip()
        if not resolved:
            messagebox.showinfo("Resolved URL", "No resolved URL is available yet.")
            return

        self.root.clipboard_clear()
        self.root.clipboard_append(resolved)

    def copy_command(self) -> None:
        command = self.command_var.get().strip()
        if not command:
            messagebox.showinfo("Command", "No command has been built yet.")
            return

        self.root.clipboard_clear()
        self.root.clipboard_append(command)

    def clear_log(self) -> None:
        self.log_text.configure(state=tk.NORMAL)
        self.log_text.delete("1.0", tk.END)
        self.log_text.configure(state=tk.DISABLED)

    def _on_url_changed(self, *_args: object) -> None:
        self._maybe_suggest_filename(self.url_var.get().strip())

    def _on_filename_changed(self, *_args: object) -> None:
        if self._updating_filename:
            return

        self.filename_autofilled = False

    def start_download(self) -> None:
        if self.process is not None or (self.download_thread and self.download_thread.is_alive()):
            messagebox.showinfo("Download Running", "A download is already in progress.")
            return

        validation_error = self._validate_inputs()
        if validation_error:
            messagebox.showerror("Validation Error", validation_error)
            return

        self.stop_requested = False
        self.status_var.set("Running")
        self.resolved_url_var.set("")
        self.command_var.set("")
        self._set_running_state(True)
        self._append_log("Preparing download...")

        self.download_thread = threading.Thread(target=self._download_worker, daemon=True)
        self.download_thread.start()

    def stop_download(self) -> None:
        self.stop_requested = True
        self._append_log("Stop requested. Attempting graceful shutdown...")

        if self.process is None:
            return

        try:
            os.killpg(self.process.pid, signal.SIGINT)
        except ProcessLookupError:
            pass
        except OSError as exc:
            self._append_log(f"Unable to signal process group cleanly: {exc}")
            try:
                self.process.terminate()
            except OSError:
                pass

    def _validate_inputs(self) -> str | None:
        url = self.url_var.get().strip()
        folder = self.folder_var.get().strip()

        if not url:
            return "Enter a download URL."

        if not (url.startswith("http://") or url.startswith("https://")):
            return "URL must start with http:// or https://."

        if not folder:
            return "Choose a save folder."

        if not os.path.isdir(folder):
            return "The save folder does not exist."

        filename = self.filename_var.get().strip()
        if filename:
            pure_name = os.path.basename(filename)
            if filename != pure_name or filename in {".", ".."}:
                return "Output filename must be a filename only, not a path."

        if shutil.which("aria2c") is None:
            return "aria2c was not found on PATH. Install it with Homebrew first."

        if self.keep_awake_var.get() and shutil.which("caffeinate") is None:
            return "caffeinate was not found on PATH."

        try:
            numeric_fields = (
                ("Connections", int(self.connections_var.get())),
                ("Splits", int(self.splits_var.get())),
            )
        except (tk.TclError, ValueError):
            return "Connections and splits must be whole numbers."

        for label, value in numeric_fields:
            if not (MIN_PARALLEL_VALUE <= value <= MAX_PARALLEL_VALUE):
                return f"{label} must be between {MIN_PARALLEL_VALUE} and {MAX_PARALLEL_VALUE}."

        return None

    def _download_worker(self) -> None:
        try:
            input_url = self.url_var.get().strip()
            target_folder = self.folder_var.get().strip()
            self.last_folder = target_folder

            if self.resolve_var.get():
                self.log_queue.put(("log", "Resolving final URL..."))
                resolved_url = RedirectResolver.resolve(input_url)
                self.log_queue.put(("resolved_url", resolved_url))
                self.log_queue.put(("log", f"Resolved URL: {resolved_url}"))
            else:
                resolved_url = input_url
                self.log_queue.put(("resolved_url", resolved_url))

            suggested_filename = self._derive_filename(resolved_url, fallback="")
            if suggested_filename:
                self.log_queue.put(("suggested_filename", suggested_filename))

            if self.stop_requested:
                self.log_queue.put(("finished", {"status": "Stopped"}))
                return

            filename = self.filename_var.get().strip() or suggested_filename or self._derive_filename(resolved_url)
            save_path = os.path.join(target_folder, filename)
            command = self._build_command(resolved_url, target_folder, filename)

            self.log_queue.put(("command", self._format_command(command)))
            self.log_queue.put(("log", f"Saving to: {save_path}"))
            self.log_queue.put(("log", "Starting aria2c..."))

            self.process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                start_new_session=True,
            )

            assert self.process.stdout is not None
            for line in self.process.stdout:
                self.log_queue.put(("log", line.rstrip()))

            return_code = self.process.wait()

            if self.stop_requested:
                self.log_queue.put(("finished", {"status": "Stopped", "saved_path": save_path}))
            elif return_code == 0:
                self.log_queue.put(("finished", {"status": "Completed", "saved_path": save_path}))
            else:
                self.log_queue.put(
                    (
                        "finished",
                        {
                            "status": "Failed",
                            "saved_path": save_path,
                            "error": f"aria2c exited with code {return_code}.",
                        },
                    )
                )
        except Exception as exc:
            self.log_queue.put(
                (
                    "finished",
                    {
                        "status": "Failed",
                        "error": str(exc),
                    },
                )
            )
        finally:
            self.process = None

    def _build_command(self, url: str, directory: str, filename: str) -> list[str]:
        aria_args = [
            "aria2c",
            "-c",
            f"-x{int(self.connections_var.get())}",
            f"-s{int(self.splits_var.get())}",
            "--file-allocation=none",
            "--dir",
            directory,
            "--out",
            filename,
            url,
        ]

        if self.keep_awake_var.get():
            return ["caffeinate", "-di", *aria_args]

        return aria_args

    def _derive_filename(self, url: str, fallback: str = "download.bin") -> str:
        parsed = urllib.parse.urlparse(url)
        path_name = PurePosixPath(parsed.path).name
        if path_name:
            return urllib.parse.unquote(path_name)
        return fallback

    def _maybe_suggest_filename(self, url: str) -> None:
        current_filename = self.filename_var.get().strip()
        if current_filename and not self.filename_autofilled:
            return

        suggested_filename = self._derive_filename(url, fallback="")
        if not self._is_confident_filename(suggested_filename):
            return

        if current_filename == suggested_filename and self.filename_autofilled:
            return

        self._updating_filename = True
        try:
            self.filename_var.set(suggested_filename)
            self.filename_autofilled = True
        finally:
            self._updating_filename = False

    def _is_confident_filename(self, filename: str) -> bool:
        return bool(filename and "." in filename.lstrip("."))

    def _format_command(self, command: list[str]) -> str:
        return " ".join(shlex.quote(part) for part in command)

    def _process_queue(self) -> None:
        try:
            while True:
                item_type, payload = self.log_queue.get_nowait()
                if item_type == "log":
                    self._append_log(str(payload))
                elif item_type == "resolved_url":
                    self.resolved_url_var.set(str(payload))
                elif item_type == "suggested_filename":
                    self._maybe_suggest_filename(str(payload))
                elif item_type == "command":
                    self.command_var.set(str(payload))
                elif item_type == "finished":
                    self._handle_finished(payload)
        except queue.Empty:
            pass
        finally:
            try:
                self.root.after(POLL_INTERVAL_MS, self._process_queue)
            except tk.TclError:
                pass

    def _handle_finished(self, payload: object) -> None:
        data = payload if isinstance(payload, dict) else {}
        status = str(data.get("status", "Failed"))
        saved_path = str(data.get("saved_path", ""))
        error = str(data.get("error", ""))

        self.status_var.set(status)
        self._set_running_state(False)

        if status == "Completed":
            self._append_log("Download completed successfully.")
            messagebox.showinfo("Download Complete", f"File saved to:\n{saved_path}")
        elif status == "Stopped":
            self._append_log("Download stopped by user.")
        else:
            self._append_log(f"Download failed: {error}")
            messagebox.showerror("Download Failed", error or "The download failed.")

    def _set_running_state(self, running: bool) -> None:
        self.start_button.configure(state=tk.DISABLED if running else tk.NORMAL)
        self.stop_button.configure(state=tk.NORMAL if running else tk.DISABLED)

    def _append_log(self, message: str) -> None:
        self.log_text.configure(state=tk.NORMAL)
        self.log_text.insert(tk.END, message + "\n")
        self.log_text.see(tk.END)
        self.log_text.configure(state=tk.DISABLED)

    def _on_close(self) -> None:
        if self.download_thread and self.download_thread.is_alive():
            if not messagebox.askyesno("Quit", "A download is running. Stop it and quit?"):
                return
            if not self.stop_requested:
                self.stop_download()
        self.root.destroy()


def main() -> None:
    root = tk.Tk()
    ttk.Style().theme_use("clam")
    DownloaderApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
