import os, select, socket, sys, termios, tty

if len(sys.argv) != 4 or sys.argv[3] not in ("raw", "plain"):
    sys.exit("usage: anon-vsock <uds> <port> raw|plain")
uds, port, mode = sys.argv[1], int(sys.argv[2]), sys.argv[3]

try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(uds)
except OSError as e:
    sys.exit("anon-vsock: cannot open %s: %s" % (uds, e))

s.sendall(b"CONNECT %d\n" % port)
# The handshake reply is a single line. Read it a byte at a time so no
# payload is swallowed with it.
reply = b""
while not reply.endswith(b"\n"):
    c = s.recv(1)
    if not c:
        sys.exit("anon-vsock: guest closed during handshake "
                 "(nothing listening on port %d?)" % port)
    reply += c
if not reply.startswith(b"OK"):
    sys.exit("anon-vsock: guest refused port %d: %s"
             % (port, reply.decode(errors="replace").strip()))

fd = sys.stdin.fileno()
saved = None
if mode == "raw" and os.isatty(fd):
    saved = termios.tcgetattr(fd)
    tty.setraw(fd)
watch_stdin = True
try:
    while True:
        rlist = [s] + ([fd] if watch_stdin else [])
        r, _, _ = select.select(rlist, [], [])
        if s in r:
            data = s.recv(65536)
            if not data:
                break
            os.write(sys.stdout.fileno(), data)
        if watch_stdin and fd in r:
            try:
                data = os.read(fd, 65536)
            except OSError:
                data = b""
            if not data:
                # stdin ended. Half-close so the guest sees EOF, but KEEP
                # reading its reply — breaking here abandoned the socket
                # before the answer arrived, which silently truncated
                # every non-interactive use (the L5 probe included, since
                # command substitution hands it a closed stdin).
                watch_stdin = False
                try:
                    s.shutdown(socket.SHUT_WR)
                except OSError:
                    pass
                continue
            s.sendall(data)
except (OSError, BrokenPipeError):
    pass
finally:
    if saved is not None:
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)
