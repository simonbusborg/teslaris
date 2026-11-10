#!/usr/bin/env python3
"""Local mock of the Tesla Fleet API for end-to-end testing without a car.

Serves the documented response shapes on the real paths, including the
failure modes that matter: 408 (asleep) and 401 (expired token).

Usage:
    python3 mock-server/mock_fleet_api.py            # port 4321
    defaults write com.weareheavy.teslaris debug_base_url http://localhost:4321

Scenario control (curl or browser):
    /debug/scenario/charging     battery climbs, 11 kW
    /debug/scenario/idle         parked, unplugged (default)
    /debug/scenario/plugged      plugged in, waiting
    /debug/scenario/complete     charged to the limit
    /debug/scenario/open         unlocked, a window and the trunk open
    /debug/scenario/tyre         rear-left tyre low, flagged by the car
    /debug/scenario/asleep       vehicle_data returns 408; wake_up wakes it
                                 to idle about 8 s later
    /debug/scenario/nowake       asleep, and wake_up returns 403 (token
                                 without vehicle_cmds)
    /debug/scenario/unregistered vehicle list returns 412
    /debug/scenario/wrongregion  vehicle list returns 421
"""

import json
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = 4321
STATE = {"scenario": "idle", "battery": 62.0, "awake_at": None}

SCENARIOS = {
    "idle":     {"charging_state": "Disconnected"},
    "plugged":  {"charging_state": "Stopped"},
    "charging": {"charging_state": "Charging", "charger_power": 11},
    "complete": {"charging_state": "Complete"},
    "open":     {"charging_state": "Disconnected", "open": True},
    "tyre":     {"charging_state": "Disconnected", "tyre": True},
    "asleep":   {},
    "nowake":   {},
    "unregistered": {},
    "wrongregion":  {},
}

ASLEEP = ("asleep", "nowake")


def settle_wake():
    """A wake lands a few seconds after it was sent, like the real car."""
    if STATE["awake_at"] and time.time() >= STATE["awake_at"]:
        STATE["scenario"] = "idle"
        STATE["awake_at"] = None


def vehicle_data():
    scenario = STATE["scenario"]
    extra = SCENARIOS[scenario]
    if scenario == "charging":
        STATE["battery"] = min(STATE["battery"] + 1.5, 90.0)
    battery = STATE["battery"]
    minutes = int((90 - battery) * 4) if scenario == "charging" else 0
    return {
        "response": {
            "id": 100021,
            "vin": "5YJ3E1EA1NF000000",
            "display_name": "Mock S",
            "state": "online",
            "charge_state": {
                "battery_level": int(battery),
                "battery_range": battery * 2.05,   # miles
                "charging_state": extra.get("charging_state", "Disconnected"),
                "charge_limit_soc": 90,
                "charger_power": extra.get("charger_power", 0),
                "minutes_to_full_charge": minutes,
                "timestamp": int(time.time() * 1000),
            },
            "vehicle_state": {
                "odometer": 14548.55,
                "vehicle_name": "Mock S",
                "locked": not extra.get("open"),
                "sentry_mode": False,
                "fd_window": 1 if extra.get("open") else 0,
                "fp_window": 0,
                "rd_window": 0,
                "rp_window": 0,
                "df": 0, "pf": 0, "dr": 0, "pr": 0,
                "ft": 0,
                "rt": 1 if extra.get("open") else 0,
                "is_user_present": False,
                "tpms_pressure_fl": 2.9, "tpms_pressure_fr": 2.9,
                "tpms_pressure_rl": 2.1 if extra.get("tyre") else 2.9,
                "tpms_pressure_rr": 2.9,
                "tpms_soft_warning_fl": False, "tpms_soft_warning_fr": False,
                "tpms_soft_warning_rl": bool(extra.get("tyre")),
                "tpms_soft_warning_rr": False,
                "tpms_hard_warning_fl": False, "tpms_hard_warning_fr": False,
                "tpms_hard_warning_rl": False, "tpms_hard_warning_rr": False,
                "software_update": {
                    "status": "available" if scenario == "idle" else "",
                    "version": "2026.20.6",
                },
                "timestamp": int(time.time() * 1000),
            },
            "climate_state": {
                "inside_temp": 22.5,
                "outside_temp": 14.0,
                "is_climate_on": False,
                "is_preconditioning": False,
                "timestamp": int(time.time() * 1000),
            },
            "gui_settings": {
                "gui_distance_units": "km/hr",
                "gui_temperature_units": "C",
                "gui_tirepressure_units": "Bar",
                "timestamp": int(time.time() * 1000),
            },
            "vehicle_config": {
                "car_type": "model3",
                "exterior_color": "UltraRed",
                "wheel_type": "Nova19",
                "timestamp": int(time.time() * 1000),
            },
        }
    }


class Handler(BaseHTTPRequestHandler):
    def _json(self, payload, status=200):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path == "/oauth2/v3/token":
            self._json({
                "access_token": "mock-access-token",
                "refresh_token": "mock-refresh-token",
                "expires_in": 3600,
                "token_type": "Bearer",
            })
        elif self.path.endswith("/wake_up"):
            if STATE["scenario"] == "nowake":
                self._json({"error": "Unauthorized missing scopes"}, 403)
                return
            if STATE["scenario"] == "asleep" and not STATE["awake_at"]:
                STATE["awake_at"] = time.time() + 8
            settle_wake()
            self._json({"response": {
                "vin": "5YJ3E1EA1NF000000",
                "state": "asleep" if STATE["scenario"] in ASLEEP else "online",
            }})
        elif self.path == "/api/1/partner_accounts":
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length) or b"{}")
            self._json({"response": {"domain": body.get("domain", "")}})
        else:
            self._json({"error": "not found"}, 404)

    def do_GET(self):
        if self.path.startswith("/debug/scenario/"):
            name = self.path.rsplit("/", 1)[-1]
            if name in SCENARIOS:
                STATE["scenario"] = name
                STATE["awake_at"] = None
                self._json({"ok": True, "scenario": name})
            else:
                self._json({"error": f"unknown scenario, pick one of {list(SCENARIOS)}"}, 400)
        elif self.path == "/api/1/vehicles" and STATE["scenario"] == "unregistered":
            self._json({"response": None, "error": "Account must be registered in the "
                        "current region"}, 412)
        elif self.path == "/api/1/vehicles" and STATE["scenario"] == "wrongregion":
            self._json({"response": None, "error": "user out of region"}, 421)
        elif self.path == "/api/1/vehicles":
            settle_wake()
            self._json({"response": [{
                "vin": "5YJ3E1EA1NF000000",
                "display_name": "Mock S",
                "state": "asleep" if STATE["scenario"] in ASLEEP else "online",
            }], "count": 1})
        elif "/vehicle_data" in self.path:
            settle_wake()
            if self.headers.get("Authorization") != "Bearer mock-access-token":
                self._json({"error": "invalid token"}, 401)
            elif STATE["scenario"] in ASLEEP:
                self._json({"error": "vehicle unavailable"}, 408)
            else:
                self._json(vehicle_data())
        else:
            self._json({"error": "not found"}, 404)

    def log_message(self, fmt, *args):
        print(f"[mock] {self.command} {self.path} → {args[1] if len(args) > 1 else ''}")


if __name__ == "__main__":
    print(f"Mock Fleet API on http://localhost:{PORT} — scenario: {STATE['scenario']}")
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
