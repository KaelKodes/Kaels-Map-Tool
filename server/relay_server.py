#!/usr/bin/env python3
"""Kaels Map Tool — Internet lobby relay.

Both host and clients connect outbound to this server (works through NAT).
Deploy on any VPS / Railway / Fly.io and point the Godot app at ws(s)://host:9090

Usage:
  pip install -r requirements.txt
  python relay_server.py
"""

from __future__ import annotations

import asyncio
import json
import logging
import random
from dataclasses import dataclass, field
from typing import Any

import websockets
from websockets.server import WebSocketServerProtocol

HOST = "0.0.0.0"
PORT = 9090
MAX_CLIENTS_PER_LOBBY = 4

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
log = logging.getLogger("relay")


@dataclass
class Room:
    code: str
    peers: dict[int, WebSocketServerProtocol] = field(default_factory=dict)
    next_id: int = 2

    def peer_ids(self) -> list[int]:
        return sorted(self.peers.keys())


rooms: dict[str, Room] = {}
ws_index: dict[WebSocketServerProtocol, tuple[str, int]] = {}


def new_code() -> str:
    for _ in range(100):
        code = f"{random.randint(0, 999999):06d}"
        if code not in rooms:
            return code
    raise RuntimeError("Could not allocate lobby code")


async def send_json(ws: WebSocketServerProtocol, payload: dict[str, Any]) -> None:
    await ws.send(json.dumps(payload))


async def broadcast_room(
    room: Room,
    payload: dict[str, Any],
    *,
    exclude: WebSocketServerProtocol | None = None,
) -> None:
    dead: list[tuple[WebSocketServerProtocol, int]] = []
    for peer_id, peer_ws in room.peers.items():
        if peer_ws is exclude:
            continue
        try:
            await send_json(peer_ws, payload)
        except websockets.ConnectionClosed:
            dead.append((peer_ws, peer_id))
    for peer_ws, peer_id in dead:
        await remove_peer(room.code, peer_ws, peer_id)


async def remove_peer(code: str, ws: WebSocketServerProtocol, peer_id: int) -> None:
    room = rooms.get(code)
    if room is None:
        return
    room.peers.pop(peer_id, None)
    ws_index.pop(ws, None)
    if len(room.peers) == 0:
        rooms.pop(code, None)
        log.info("Lobby %s closed (empty)", code)
        return
    await broadcast_room(room, {"op": "peer_disconnected", "peer_id": peer_id}, exclude=ws)
    log.info("Peer %d left lobby %s", peer_id, code)


async def handler(ws: WebSocketServerProtocol) -> None:
    room_code: str | None = None
    peer_id: int | None = None
    try:
        async for raw in ws:
            try:
                data = json.loads(raw)
            except json.JSONDecodeError:
                await send_json(ws, {"op": "error", "msg": "Invalid JSON"})
                continue

            op = data.get("op")
            if op == "host":
                if len(rooms) > 5000:
                    await send_json(ws, {"op": "error", "msg": "Server full"})
                    continue
                code = new_code()
                room = Room(code=code)
                room.peers[1] = ws
                rooms[code] = room
                room_code = code
                peer_id = 1
                ws_index[ws] = (code, 1)
                await send_json(ws, {"op": "hosted", "code": code, "peer_id": 1, "peers": [1]})
                log.info("Lobby %s created", code)
                continue

            if op == "join":
                code = str(data.get("code", "")).strip()
                room = rooms.get(code)
                if room is None:
                    await send_json(ws, {"op": "error", "msg": "Lobby not found"})
                    continue
                if len(room.peers) >= MAX_CLIENTS_PER_LOBBY:
                    await send_json(ws, {"op": "error", "msg": "Lobby is full"})
                    continue
                peer_id = room.next_id
                room.next_id += 1
                room.peers[peer_id] = ws
                room_code = code
                ws_index[ws] = (code, peer_id)
                await send_json(
                    ws,
                    {
                        "op": "joined",
                        "code": code,
                        "peer_id": peer_id,
                        "peers": room.peer_ids(),
                    },
                )
                await broadcast_room(
                    room,
                    {"op": "peer_connected", "peer_id": peer_id, "peers": room.peer_ids()},
                    exclude=ws,
                )
                log.info("Peer %d joined lobby %s", peer_id, code)
                continue

            if op == "rpc":
                if ws not in ws_index:
                    continue
                code, sender_id = ws_index[ws]
                room = rooms.get(code)
                if room is None:
                    continue
                targets = data.get("targets", [])
                payload = {
                    "op": "rpc",
                    "from": sender_id,
                    "method": data.get("method", ""),
                    "args": data.get("args", []),
                }
                if not targets:
                    await broadcast_room(room, payload, exclude=ws)
                else:
                    for target in targets:
                        target_ws = room.peers.get(int(target))
                        if target_ws is not None and target_ws is not ws:
                            await send_json(target_ws, payload)
                continue

            await send_json(ws, {"op": "error", "msg": f"Unknown op: {op}"})

    except websockets.ConnectionClosed:
        pass
    finally:
        if room_code is not None and peer_id is not None:
            await remove_peer(room_code, ws, peer_id)


async def main() -> None:
    log.info("Relay listening on %s:%d", HOST, PORT)
    async with websockets.serve(handler, HOST, PORT, ping_interval=20, ping_timeout=20):
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
