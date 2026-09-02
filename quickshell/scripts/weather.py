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
  "feelsLikeC": float|null, "humidity": int|null, "windKph": float|null,
  "hourly": [{"hour": "HH:00", "tempC": float, "code": int,
              "precipProb": int}, ...],  (next 8h)
  "daily": [{"date": "YYYY-MM-DD", "code": int, "tempMax": float,
             "tempMin": float, "precipProb": int, "precipMm": float}, ...]  (7 days)
}
On a successful fetch this also overwrites CACHE_FILE, and a failed fetch
(offline, rate limited, etc.) falls back to reading it instead of emitting
nulls — so a restart of quickshell (which re-runs this from scratch, no
persisted state of its own) or a spell of no connectivity shows the last
known reading rather than a blank widget. Only emit all-null if there's
truly nothing cached yet (e.g. first run ever, offline).
"""
import json
import os
import sys
import urllib.request

GEO_URL = "http://ip-api.com/json/"
FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
CACHE_FILE = os.path.expanduser("~/.config/quickshell/weather-cache.json")

EMPTY_RESULT = {"tempC": None, "code": None, "isDay": None, "city": "",
                "feelsLikeC": None, "humidity": None, "windKph": None,
                "hourly": [], "daily": []}


def fetch_json(url, timeout=8):
    with urllib.request.urlopen(url, timeout=timeout) as resp:
        return json.load(resp)


def load_cache():
    try:
        with open(CACHE_FILE, encoding="utf-8") as f:
            cached = json.load(f)
        if cached.get("tempC") is not None:
            return cached
    except (OSError, ValueError, TypeError):
        pass
    return None


def save_cache(result):
    try:
        os.makedirs(os.path.dirname(CACHE_FILE), exist_ok=True)
        with open(CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(result, f)
    except OSError:
        pass


def fetch_live():
    result = dict(EMPTY_RESULT, hourly=[], daily=[])
    geo = fetch_json(GEO_URL)
    lat, lon = geo["lat"], geo["lon"]
    url = (f"{FORECAST_URL}?latitude={lat}&longitude={lon}"
           "&current=temperature_2m,weather_code,is_day,apparent_temperature,relative_humidity_2m,wind_speed_10m"
           "&hourly=temperature_2m,weather_code,precipitation_probability"
           "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum"
           "&timezone=auto&forecast_days=7")
    data = fetch_json(url)

    current = data.get("current", {})
    result["tempC"] = current.get("temperature_2m")
    result["code"] = current.get("weather_code")
    result["isDay"] = bool(current.get("is_day", 1))
    result["city"] = geo.get("city", "")
    result["feelsLikeC"] = current.get("apparent_temperature")
    result["humidity"] = current.get("relative_humidity_2m")
    result["windKph"] = current.get("wind_speed_10m")

    hourly = data.get("hourly", {})
    times = hourly.get("time", [])
    temps = hourly.get("temperature_2m", [])
    codes = hourly.get("weather_code", [])
    precip_probs = hourly.get("precipitation_probability", [])
    now = current.get("time", "")
    now_hour = now[:13] + ":00" if len(now) >= 13 else ""
    start = times.index(now_hour) if now_hour in times else 0
    for t, temp, code, precip in list(zip(times, temps, codes, precip_probs))[start:start + 8]:
        result["hourly"].append({"hour": t[11:16], "tempC": temp, "code": code, "precipProb": precip})

    daily = data.get("daily", {})
    for date, code, tmax, tmin, precip, precip_mm in zip(
        daily.get("time", []), daily.get("weather_code", []),
        daily.get("temperature_2m_max", []), daily.get("temperature_2m_min", []),
        daily.get("precipitation_probability_max", []),
        daily.get("precipitation_sum", []),
    ):
        result["daily"].append({"date": date, "code": code, "tempMax": tmax, "tempMin": tmin,
                                 "precipProb": precip, "precipMm": precip_mm})
    return result


def main():
    try:
        result = fetch_live()
        save_cache(result)
    except (OSError, KeyError, ValueError, TypeError):
        result = load_cache() or dict(EMPTY_RESULT)
    json.dump(result, sys.stdout)


if __name__ == "__main__":
    main()
