# Optional standalone relay (legacy)

The game embeds a lobby server in the **host client**. Join with the host's IP — no lobby code.

This Python relay is only needed for separate testing; normal play does not use it.

```bash
pip install -r requirements.txt
python relay_server.py
```

## Multiplayer flow

1. **Host** — click Host; share the IP shown (LAN IP for same Wi‑Fi, public IP for internet).
2. **Join** — enter that IP and click Join.
3. Internet hosts may need port **9090** forwarded on their router.
