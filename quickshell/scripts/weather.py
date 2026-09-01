#!/usr/bin/env python3
"""Current + today's hourly + 7-day weather for the bar's Weather widget
(Weather.qml) and its forecast popup.

Location is auto-detected via IP geolocation (ip-api.com, free, no key) —
there's no location configured anywhere else on this machine, and asking
for one upfront isn't worth it when auto-detect already lands correctly.
Conditions come from Open-Meteo (api.open-meteo.com), also free and keyless.

Emits one JSON line:
{
  "tempC": float|null, "code": int|null, "isDay": bool|null, "city": str,
  "hourly": [{"hour": "HH:00", "tempC": float, "code": int}, ...],  (next 8h)
  "daily": [{"date": "YYYY-MM-DD", "code": int,
             "tempMax": float, "tempMin": float, "precipProb": int}, ...]  (7 days)
}
All top-level fields are null/empty if either lookup fails (offline, rate
limited, etc.) — the widget shows nothing rather than a wrong reading.
"""
import json
import sys
import urllib.request

GEO_URL = "http://ip-api.com/json/"
FORECAST_URL = "https://api.open-meteo.com/v1/forecast"


def fetch_json(url, timeout=8):
    with urllib.request.urlopen(url, timeout=timeout) as resp:
        return json.load(resp)


def main():
    result = {"tempC": None, "code": None, "isDay": None, "city": "",
              "hourly": [], "daily": []}
    try:
        geo = fetch_json(GEO_URL)
        lat, lon = geo["lat"], geo["lon"]
        url = (f"{FORECAST_URL}?latitude={lat}&longitude={lon}"
               "&current=temperature_2m,weather_code,is_day"
               "&hourly=temperature_2m,weather_code"
               "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"
               "&timezone=auto&forecast_days=7")
        data = fetch_json(url)

        current = data.get("current", {})
        result["tempC"] = current.get("temperature_2m")
        result["code"] = current.get("weather_code")
        result["isDay"] = bool(current.get("is_day", 1))
        result["city"] = geo.get("city", "")

        hourly = data.get("hourly", {})
        times = hourly.get("time", [])
        temps = hourly.get("temperature_2m", [])
        codes = hourly.get("weather_code", [])
        now = current.get("time", "")
        now_hour = now[:13] + ":00" if len(now) >= 13 else ""
        start = times.index(now_hour) if now_hour in times else 0
        for t, temp, code in list(zip(times, temps, codes))[start:start + 8]:
            result["hourly"].append({"hour": t[11:16], "tempC": temp, "code": code})

        daily = data.get("daily", {})
        for date, code, tmax, tmin, precip in zip(
            daily.get("time", []), daily.get("weather_code", []),
            daily.get("temperature_2m_max", []), daily.get("temperature_2m_min", []),
            daily.get("precipitation_probability_max", []),
        ):
            result["daily"].append({"date": date, "code": code,
                                     "tempMax": tmax, "tempMin": tmin, "precipProb": precip})
    except (OSError, KeyError, ValueError, TypeError):
        pass
    json.dump(result, sys.stdout)


if __name__ == "__main__":
    main()
