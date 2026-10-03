"""Integration test against the actual SimuCNC TCP server (no printer required)."""
import socket, subprocess, time
from pathlib import Path
exe=Path(__file__).resolve().parents[1]/'src/simucnc/SimuCNC.exe'
startup=subprocess.STARTUPINFO(); startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW; startup.wShowWindow=0
p=subprocess.Popen([str(exe),'-tcp','-grbl'],startupinfo=startup)
def read_until(s, token):
    data=b''
    deadline=time.monotonic()+8
    while token not in data and time.monotonic()<deadline:
        chunk=s.recv(8192)
        assert chunk, 'unexpected disconnect'
        data+=chunk
    assert token in data, data
    return data
try:
    for _ in range(10):
        try:
            s=socket.create_connection(('127.0.0.1',9000),timeout=1); break
        except OSError:
            assert p.poll() is None, 'SimuCNC exited'
            time.sleep(.1)
    else: raise AssertionError('TCP listener failed')
    s.settimeout(8)
    assert b'start' in read_until(s,b'start')
    s.sendall(b'M11'); time.sleep(.2); s.sendall(b'5\r\n')
    response=read_until(s,b'ok')
    assert b'FIRMWARE_NAME' in response, response
    s.sendall(b'G90\nG1 X10 Y20 F6000\n')
    time.sleep(.8)
    s.sendall(b'M114\n')
    response=read_until(s,b'X:10')
    assert b'Y:20' in response, response
    s.sendall(b'$J=G91 Z5.000 F600\n')
    assert b'ok' in read_until(s,b'ok')
    time.sleep(.8)
    s.sendall(b'M114\n')
    response=read_until(s,b'Z:5')
    assert b'X:10' in response and b'Y:20' in response, response
    s.sendall(b'M105\n')
    assert b'T:' in read_until(s,b'T:')
    s.close(); time.sleep(.3)
    with socket.create_connection(('127.0.0.1',9000),timeout=3) as s:
        read_until(s,b'start')
        s.sendall(b'M114\n')
        assert b'X:0' in read_until(s,b'X:0')
    time.sleep(.3)
    client=Path(__file__).resolve().parent/'lib/test_multicnc_tcp.exe'
    assert client.exists(), 'Compile tests/test_multicnc_tcp.lpr first'
    subprocess.run([str(client)], check=True, timeout=25)
    print('PASS: startup, fragmented command, CRLF, batch, movement, temperature, disconnect/reconnect')
finally:
    p.terminate(); p.wait(timeout=5)


