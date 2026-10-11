#!/usr/bin/env python3
"""BlueZ pairing agent for the bar's Bluetooth menu (BluetoothAgent.qml).

Nothing else on this setup registers one (no blueman/gnome-bluetooth), and
without an agent BlueZ can only do "Just Works" pairing: phones, keyboards and
anything else that shows or asks for a code fail to pair. This registers a
KeyboardDisplay agent as the default and hands every request to QML:

  stdout, one JSON object per line:
    {"id": 3, "type": "confirm", "device": "/org/bluez/...", "name": "Pixel",
     "passkey": "012345"}
    type is one of: confirm (RequestConfirmation), authorize
    (RequestAuthorization), pin / passkey (RequestPinCode / RequestPasskey --
    user types it), display-pin / display-passkey (show a code to type on the
    device; no answer expected), cancel (BlueZ gave up; drop any prompt).
  stdin, one answer per line:  "<id> yes" | "<id> no" | "<id> <code>"

AuthorizeService for an already-paired device is accepted without asking:
that's a known device (re)connecting a profile, not a new pairing.
"""
import json
import sys

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

AGENT_PATH = "/org/sichos/btagent"
AGENT_IFACE = "org.bluez.Agent1"


class Rejected(dbus.DBusException):
    _dbus_error_name = "org.bluez.Error.Rejected"


class Canceled(dbus.DBusException):
    _dbus_error_name = "org.bluez.Error.Canceled"


bus = None
pending = {}  # id -> (kind, reply, error)
next_id = 0


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def device_props(path):
    try:
        props = dbus.Interface(bus.get_object("org.bluez", path), "org.freedesktop.DBus.Properties")
        return props.GetAll("org.bluez.Device1")
    except dbus.DBusException:
        return {}


def device_name(path):
    p = device_props(path)
    return str(p.get("Alias") or p.get("Name") or p.get("Address") or path.rsplit("/", 1)[-1])


def ask(kind, device, reply, error, **extra):
    global next_id
    next_id += 1
    pending[next_id] = (kind, reply, error, str(device))
    emit(dict(id=next_id, type=kind, device=str(device), name=device_name(device), **extra))


def set_trusted(path):
    # A device paired through us should reconnect later without asking again.
    try:
        props = dbus.Interface(bus.get_object("org.bluez", path), "org.freedesktop.DBus.Properties")
        props.Set("org.bluez.Device1", "Trusted", dbus.Boolean(True))
    except dbus.DBusException:
        pass


class Agent(dbus.service.Object):
    @dbus.service.method(AGENT_IFACE, in_signature="", out_signature="")
    def Release(self):
        pass

    @dbus.service.method(AGENT_IFACE, in_signature="os", out_signature="",
                         async_callbacks=("reply", "error"))
    def AuthorizeService(self, device, uuid, reply, error):
        if device_props(device).get("Paired"):
            reply()
        else:
            ask("authorize", device, reply, error)

    @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="s",
                         async_callbacks=("reply", "error"))
    def RequestPinCode(self, device, reply, error):
        ask("pin", device, reply, error)

    @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="u",
                         async_callbacks=("reply", "error"))
    def RequestPasskey(self, device, reply, error):
        ask("passkey", device, reply, error)

    @dbus.service.method(AGENT_IFACE, in_signature="ouq", out_signature="")
    def DisplayPasskey(self, device, passkey, entered):
        emit(dict(id=0, type="display-passkey", device=str(device), name=device_name(device),
                  passkey="%06d" % passkey, entered=int(entered)))

    @dbus.service.method(AGENT_IFACE, in_signature="os", out_signature="")
    def DisplayPinCode(self, device, pincode):
        emit(dict(id=0, type="display-pin", device=str(device), name=device_name(device),
                  passkey=str(pincode)))

    @dbus.service.method(AGENT_IFACE, in_signature="ou", out_signature="",
                         async_callbacks=("reply", "error"))
    def RequestConfirmation(self, device, passkey, reply, error):
        ask("confirm", device, reply, error, passkey="%06d" % passkey)

    @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="",
                         async_callbacks=("reply", "error"))
    def RequestAuthorization(self, device, reply, error):
        ask("authorize", device, reply, error)

    @dbus.service.method(AGENT_IFACE, in_signature="", out_signature="")
    def Cancel(self):
        for kind, reply, error, device in pending.values():
            error(Canceled("Canceled"))
        pending.clear()
        emit(dict(id=0, type="cancel"))


def on_stdin(source, condition):
    line = sys.stdin.readline()
    if not line:  # quickshell went away
        loop.quit()
        return False
    parts = line.strip().split(" ", 1)
    if len(parts) != 2 or not parts[0].isdigit():
        return True
    entry = pending.pop(int(parts[0]), None)
    if entry is None:
        return True
    kind, reply, error, device = entry
    answer = parts[1]
    if answer == "no":
        error(Rejected("Rejected by user"))
    elif kind == "pin":
        reply(dbus.String(answer))
        set_trusted(device)
    elif kind == "passkey":
        reply(dbus.UInt32(int(answer) if answer.isdigit() else 0))
        set_trusted(device)
    else:
        reply()
        set_trusted(device)
    return True


def main():
    global bus, loop
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    Agent(bus, AGENT_PATH)
    manager = dbus.Interface(bus.get_object("org.bluez", "/org/bluez"), "org.bluez.AgentManager1")
    manager.RegisterAgent(AGENT_PATH, "KeyboardDisplay")
    manager.RequestDefaultAgent(AGENT_PATH)
    emit(dict(id=0, type="ready"))
    loop = GLib.MainLoop()
    GLib.io_add_watch(sys.stdin, GLib.IO_IN | GLib.IO_HUP, on_stdin)
    try:
        loop.run()
    finally:
        try:
            manager.UnregisterAgent(AGENT_PATH)
        except dbus.DBusException:
            pass


if __name__ == "__main__":
    main()
