"""Send protected function calls to a local Rusted Warfare 1.15 debug socket."""

from __future__ import annotations

import argparse
import socket


class DebugSession:
    """Reuse one connection because the original debug server accepts serially."""

    def __init__(self, port: int, timeout: float = 15.0) -> None:
        self.connection = socket.create_connection(("127.0.0.1", port), timeout)
        self.connection.settimeout(timeout)

    def __enter__(self) -> "DebugSession":
        return self

    def __exit__(self, *_unused: object) -> None:
        self.connection.close()

    def call(self, expression: str) -> str:
        self.connection.sendall(f"function {expression}\n".encode("utf-8"))
        response = bytearray()
        while not response.endswith(b"\x00"):
            chunk = self.connection.recv(65536)
            if not chunk:
                raise ConnectionError("Original game closed the debug socket")
            response.extend(chunk)
        message = response[:-1].decode("utf-8", errors="replace")
        if message.startswith("ok\n"):
            return message[3:]
        raise RuntimeError(f"{expression}: {message}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=5678)
    parser.add_argument("expression", nargs="+")
    arguments = parser.parse_args()
    with DebugSession(arguments.port) as session:
        for expression in arguments.expression:
            print(f"{expression} => {session.call(expression)}")


if __name__ == "__main__":
    main()
