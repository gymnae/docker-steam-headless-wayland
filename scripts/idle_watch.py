#!/usr/bin/env python3
"""Exit once no input arrived for the given number of minutes (0 = never).

Runs as the command of the Sunshine app. When it exits, Sunshine ends the stream and
runs the app's undo command, the same as quitting the session in Moonlight.
"""
import fcntl
import glob
import os
import select
import struct
import sys
import time

EV_KEY, EV_REL, EV_ABS = 0x01, 0x02, 0x03
INPUT_PROP_ACCELEROMETER = 0x06
EVENT_SIZE = 24  # struct input_event on 64-bit
# Stick/trigger moves smaller than this share of the axis range are treated as jitter
ABS_THRESHOLD = 0.1


def eviocgabs(code):
    # _IOR('E', 0x40 + code, struct input_absinfo), the struct is 6 ints
    return (2 << 30) | (24 << 16) | (ord("E") << 8) | (0x40 + code)


def is_motion_sensor(path):
    # Gyro and accelerometer nodes report constantly, even with the pad lying on a table
    try:
        with open(f"/sys/class/input/{os.path.basename(path)}/device/properties") as f:
            return int(f.read().split()[-1], 16) >> INPUT_PROP_ACCELEROMETER & 1
    except (OSError, ValueError, IndexError):
        return False


class Device:
    def __init__(self, path):
        self.fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        self.abs_state = {}  # code -> (last counted value, threshold)

    def abs_moved(self, code, value):
        if code not in self.abs_state:
            try:
                info = fcntl.ioctl(self.fd, eviocgabs(code), bytes(24))
                _, minimum, maximum, *_ = struct.unpack("6i", info)
                threshold = max(1, (maximum - minimum) * ABS_THRESHOLD)
            except OSError:
                threshold = 1
            self.abs_state[code] = (value, threshold)
            return True
        last, threshold = self.abs_state[code]
        if abs(value - last) < threshold:
            return False
        self.abs_state[code] = (value, threshold)
        return True

    def had_input(self):
        """Read pending events; True if any of them was real input. Raises OSError once the device is gone."""
        try:
            data = os.read(self.fd, EVENT_SIZE * 64)
        except BlockingIOError:
            return False
        if not data:
            raise OSError("device closed")
        active = False
        for offset in range(0, len(data) - EVENT_SIZE + 1, EVENT_SIZE):
            ev_type, code, value = struct.unpack_from("HHi", data, offset + 16)
            if ev_type in (EV_KEY, EV_REL) or (ev_type == EV_ABS and self.abs_moved(code, value)):
                active = True
        return active


def main():
    minutes = float(sys.argv[1]) if len(sys.argv) > 1 else 30
    if minutes <= 0:
        while True:
            time.sleep(3600)

    timeout = minutes * 60
    devices = {}  # path -> Device
    last_input = time.monotonic()
    next_scan = 0

    while time.monotonic() - last_input < timeout:
        if time.monotonic() >= next_scan:
            # Sunshine creates its virtual devices on connect and removes them on disconnect
            paths = {p for p in glob.glob("/dev/input/event*") if not is_motion_sensor(p)}
            for path in devices.keys() - paths:
                os.close(devices.pop(path).fd)
            for path in paths - devices.keys():
                try:
                    devices[path] = Device(path)
                except OSError:
                    pass
            next_scan = time.monotonic() + 5

        by_fd = {dev.fd: path for path, dev in devices.items()}
        ready, _, _ = select.select(list(by_fd), [], [], 5)
        for fd in ready:
            path = by_fd[fd]
            try:
                if devices[path].had_input():
                    last_input = time.monotonic()
            except OSError:
                os.close(devices.pop(path).fd)

    print(f"No input for {minutes:g} minutes, ending the stream", flush=True)


if __name__ == "__main__":
    main()
