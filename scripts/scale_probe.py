#!/usr/bin/env python3
"""
Talks to the Phoenix / Fitdays+ kitchen scale (BLE name MY_SCALE) from a Mac,
to find out what the scale really sends, using the open-source pyfitdaysplus
library as the reference.

Setup (once):
    cd scripts
    /opt/homebrew/bin/python3.12 -m venv .scale-venv
    source .scale-venv/bin/activate
    pip install pyfitdaysplus bleak

Run (close Fitdays+ and nRF Connect first - the scale talks to one app at a time,
and allow Bluetooth for Terminal when macOS asks). Keep a weight (a tin, 100 g or
more) next to the scale and follow the on-screen prompts:

    python scale_probe.py           # the library: connect, listen for weight
    python scale_probe.py --food    # the same, but first start a food-weigh session
                                    # (what Fitdays+ does when you pick a food)
    python scale_probe.py --raw     # plain Bluetooth: print every message
    python scale_probe.py --probe   # plain Bluetooth: try "set user" commands, one at a time,
                                    # with the weight left ON the scale
    python scale_probe.py --unit 5  # start the weight stream, then ask the scale to switch its
                                    # display unit (0 g, 1 ml, 2 lb:oz, 3 oz, 4 mg, 5 ml milk,
                                    # 6 fl oz, 7 fl oz milk) and print what it does
    python scale_probe.py --tare    # the same with the tare command (leave something on the scale)
    python scale_probe.py --watch   # print only what changes (weight, unit, flags) and any other
                                    # message, for 60 s: press TARE, lift things, press the buttons
    python scale_probe.py --show    # put a food on the scale's screen: name and macros per 100 g
                                    # (Oats by default; or --show "Whole Milk" 64 3.4 4.8 3.6
                                    #  = name, kcal, protein, carbs, fat). Press the scale's tick
                                    # and arrow buttons and the messages they send are printed.

Send back everything it prints.
"""
import asyncio
import sys
import time

from bleak import BleakClient, BleakScanner

NAME = "MY_SCALE"
WRITE = "0000ffb1-0000-1000-8000-00805f9b34fb"
NOTIFY = "0000ffb2-0000-1000-8000-00805f9b34fb"
HANDSHAKE = bytes.fromhex("ac42000200a000d173")
HISTORY = bytes.fromhex("ac42000000d4d4")

# (seconds from the start, what to tell the person)
PROMPTS = [
    (0, "Scale empty - leave it alone for a few seconds"),
    (6, ">>> PUT THE WEIGHT ON THE SCALE NOW <<<"),
    (16, ">>> TAKE IT OFF <<<"),
    (22, ">>> PUT IT BACK ON <<<"),
    (32, ">>> PRESS TARE ON THE SCALE <<<"),
    (40, "Finishing ..."),
]


async def prompts(started):
    for at, text in PROMPTS:
        await asyncio.sleep(max(0, started + at - time.time()))
        print(f"\n[{time.time() - started:5.1f}s] {text}\n", flush=True)


async def find():
    print(f"Looking for {NAME} ...")
    device = await BleakScanner.find_device_by_name(NAME, timeout=20)
    if device is None:
        sys.exit("Not found. Is the scale awake and free of other apps?")
    print(f"Found {device.name} at {device.address}")
    return device


async def with_library(food: bool):
    from pyfitdaysplus import Device
    from pyfitdaysplus.events import Event
    from pyfitdaysplus.models import CommonFood

    device = await find()
    scale = Device(device)
    started = time.time()
    count = 0

    def on_weight(reading):
        nonlocal count
        count += 1
        print(f"[{time.time() - started:5.1f}s] WEIGHT {reading.grams:.1f} g stable={reading.stable} "
              f"tare={reading.is_tare} unit={reading.unit.name} raw={reading.raw_payload.hex(' ')}", flush=True)

    async with scale:
        scale.subscribe(Event.WEIGHT, on_weight)
        print("Connected.", flush=True)
        if food:
            print("Starting a food-weigh session for 'oats' ...", flush=True)
            await scale.start_food_weigh(CommonFood(food_id=42, name="oats", weight=100, facts=()))
        started = time.time()
        await asyncio.gather(prompts(started), asyncio.sleep(42))
        print(f"\nDone. Weight messages received: {count}")


async def raw():
    device = await find()
    started = time.time()
    count = 0

    def show(_, data: bytearray):
        nonlocal count
        count += 1
        print(f"[{time.time() - started:5.1f}s] FFB2: {data.hex(' ')}", flush=True)

    async with BleakClient(device) as client:
        print("Connected. Subscribing to FFB2 ...")
        await client.start_notify(NOTIFY, show)
        await asyncio.sleep(3)
        print("Sending the handshake:", HANDSHAKE.hex(" "))
        await client.write_gatt_char(WRITE, HANDSHAKE, response=True)
        await asyncio.sleep(1)
        print("Asking for stored weights:", HISTORY.hex(" "))
        await client.write_gatt_char(WRITE, HISTORY, response=True)
        started = time.time()
        await asyncio.gather(prompts(started), asyncio.sleep(42))
        print(f"\nDone. Messages received on FFB2: {count}")


def frame(payload: bytes, cmd: int) -> bytes:
    """AC 42 [payload] [cmd] [checksum], checksum = sum of everything after the 42."""
    body = payload + bytes([cmd])
    return bytes([0xAC, 0x42]) + body + bytes([sum(body) & 0xFF])


def split(data: bytes) -> bytes:
    """The scale's 'split data' wrapper: total length (2 bytes), sequence 0, then the data."""
    return len(data).to_bytes(2, "big") + b"\x00" + data


# Guesses at the "tell the scale who is weighing" command. The library's notes say
# user info is command 0xDB (newer firmware, includes a user id) or 0xD0 (older).
# A command the scale understands is acknowledged with an A1 message.
CANDIDATES = [
    # Worked on a KN2432LB: the scale acknowledges it and starts streaming weight.
    ("user info DB: id 1", frame(split(bytes.fromhex("00000001")), 0xDB)),
    ("user info DB: id 1 + 8 zero bytes", frame(split(bytes.fromhex("00000001") + bytes(8)), 0xDB)),
    ("user info D0: index 1", frame(split(bytes.fromhex("01")), 0xD0)),
    ("user info D0: id 1", frame(split(bytes.fromhex("00000001")), 0xD0)),
]


async def probe():
    device = await find()
    started = time.time()
    count = 0

    def show(_, data: bytearray):
        nonlocal count
        count += 1
        print(f"[{time.time() - started:5.1f}s]   <- FFB2: {data.hex(' ')}", flush=True)

    async with BleakClient(device) as client:
        await client.start_notify(NOTIFY, show)
        print("Connected. Leave a weight ON the scale and keep nudging it.\n")
        await asyncio.sleep(2)
        print("Handshake:", HANDSHAKE.hex(" "))
        await client.write_gatt_char(WRITE, HANDSHAKE, response=True)
        await asyncio.sleep(3)
        for name, data in CANDIDATES:
            started_at = time.time() - started
            print(f"\n[{started_at:5.1f}s] -> {name}: {data.hex(' ')}", flush=True)
            await client.write_gatt_char(WRITE, data, response=True)
            await asyncio.sleep(5)
        print(f"\nDone. Messages received on FFB2: {count}")


UNIT_NAMES = {0: "g", 1: "ml", 2: "lb:oz", 3: "oz", 4: "mg", 5: "ml milk", 6: "fl oz", 7: "fl oz milk"}
USER_INFO = frame(split(bytes.fromhex("00000001")), 0xDB)


def setting(kind: int, param: int) -> bytes:
    """A D2 setting command: type 0 tare, type 2 unit."""
    return frame(bytes([0x00, 0x02, 0x00, kind, param]), 0xD2)


def describe(data: bytes) -> str:
    """One line for a message from the scale: its type, and for live weight the unit and grams."""
    if len(data) < 5 or data[0] != 0xAC:
        return data.hex(" ")
    kind = data[-2]
    text = f"type {kind:02X}"
    body = data[2:-2]
    if kind == 0xA6 and len(body) >= 8:
        d = body[3:]
        unit = d[1] >> 4
        grams = ((d[2] << 16) | (d[3] << 8) | d[4]) / 1000
        text += f" weight {grams:g} g, scale shows {UNIT_NAMES.get(unit, unit)}, flags {d[0]:02X}"
    return f"{text}   [{data.hex(' ')}]"


async def command(name: str, data: bytes):
    device = await find()
    started = time.time()

    def show(_, message: bytearray):
        print(f"[{time.time() - started:5.1f}s]   <- {describe(bytes(message))}", flush=True)

    async with BleakClient(device) as client:
        await client.start_notify(NOTIFY, show)
        print("Connected. Leave something on the scale.\n")
        await asyncio.sleep(2)
        await client.write_gatt_char(WRITE, HANDSHAKE, response=True)
        await asyncio.sleep(1)
        await client.write_gatt_char(WRITE, USER_INFO, response=True)
        await asyncio.sleep(4)
        print(f"\n[{time.time() - started:5.1f}s] -> {name}: {data.hex(' ')}\n", flush=True)
        await client.write_gatt_char(WRITE, data, response=True)
        await asyncio.sleep(8)
        print("\nDone. Did the scale's own display change? Say what it showed.")


async def show_food(name: str, kcal: float, protein: float, carbs: float, fat: float):
    from pyfitdaysplus.models import CommonFood, NutritionFact, NutritionFactType
    from pyfitdaysplus.protocol.food_write import build_set_common_food_frames

    food = CommonFood(
        food_id=7,
        name=name,
        weight=100,
        facts=(
            NutritionFact(NutritionFactType.CALORIE, kcal),
            NutritionFact(NutritionFactType.PROTEIN, protein),
            NutritionFact(NutritionFactType.CARBOHYDRATE, carbs),
            NutritionFact(NutritionFactType.FAT, fat),
        ),
    )
    frames = build_set_common_food_frames(food)
    device = await find()
    started = time.time()

    def show(_, message: bytearray):
        print(f"[{time.time() - started:5.1f}s]   <- {describe(bytes(message))}", flush=True)

    async def send(label: str):
        print(f"\n[{time.time() - started:5.1f}s] -> {label}", flush=True)
        for data in frames:
            print(f"        {data.hex(' ')}", flush=True)
            await client.write_gatt_char(WRITE, data, response=True)
            await asyncio.sleep(0.2)

    async with BleakClient(device) as client:
        await client.start_notify(NOTIFY, show)
        await asyncio.sleep(2)
        await client.write_gatt_char(WRITE, HANDSHAKE, response=True)
        await asyncio.sleep(1)
        await client.write_gatt_char(WRITE, USER_INFO, response=True)
        await asyncio.sleep(3)
        await send(f"food: {name}, {kcal:g} kcal, P {protein:g} C {carbs:g} F {fat:g} per 100 g")
        print("\n>>> LOOK AT THE SCALE'S SCREEN. In 8 seconds put something on it. <<<", flush=True)
        await asyncio.sleep(8)
        await send("the same food again (the library does this when a weight is on)")
        print("\n>>> Now press the tick and the arrow buttons on the scale, one at a time. <<<", flush=True)
        await asyncio.sleep(20)
        print("\nDone. Say what the screen showed: name, kcal, protein, carbs, fat - and whether they changed with the weight.")


async def watch():
    device = await find()
    started = time.time()
    last = {"key": None}
    prompts = [
        (6, ">>> PUT SOMETHING ON THE SCALE (a bowl or tin) and leave it <<<"),
        (16, ">>> PRESS THE TARE BUTTON ON THE SCALE <<<"),
        (26, ">>> LIFT THE THING OFF <<<"),
        (34, ">>> PUT IT BACK ON <<<"),
        (42, ">>> PRESS THE TICK BUTTON, then the arrows, one at a time <<<"),
        (56, "Finishing ..."),
    ]

    def show(_, message: bytearray):
        data = bytes(message)
        line = describe(data)
        if len(data) >= 5 and data[0] == 0xAC and data[-2] == 0xA6:
            key = data[2:-1]  # everything that matters: weight, unit and flags
            if key == last["key"]:
                return
            last["key"] = key
        print(f"[{time.time() - started:5.1f}s]   <- {line}", flush=True)

    async def prompt_loop():
        for at, text in prompts:
            await asyncio.sleep(max(0, started + at - time.time()))
            print(f"\n[{time.time() - started:5.1f}s] {text}\n", flush=True)

    async with BleakClient(device) as client:
        await client.start_notify(NOTIFY, show)
        await asyncio.sleep(2)
        await client.write_gatt_char(WRITE, HANDSHAKE, response=True)
        await asyncio.sleep(1)
        await client.write_gatt_char(WRITE, USER_INFO, response=True)
        await prompt_loop()
        print("\nDone.")


if __name__ == "__main__":
    if "--watch" in sys.argv:
        asyncio.run(watch())
        sys.exit()
    if "--show" in sys.argv:
        rest = [a for a in sys.argv[sys.argv.index("--show") + 1:] if not a.startswith("--")]
        if len(rest) >= 5:
            asyncio.run(show_food(rest[0], *map(float, rest[1:5])))
        else:
            asyncio.run(show_food("Oats", 389, 16.9, 66.3, 6.9))
        sys.exit()
    if "--unit" in sys.argv:
        code = int(sys.argv[sys.argv.index("--unit") + 1])
        asyncio.run(command(f"set unit {code} ({UNIT_NAMES.get(code, '?')})", setting(2, code)))
        sys.exit()
    if "--tare" in sys.argv:
        asyncio.run(command("tare", setting(0, 0)))
        sys.exit()
    if "--probe" in sys.argv:
        asyncio.run(probe())
        sys.exit()
    if "--raw" in sys.argv:
        asyncio.run(raw())
    else:
        asyncio.run(with_library("--food" in sys.argv))
