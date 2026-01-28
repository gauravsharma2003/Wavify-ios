import requests
import json
import urllib3
import re

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

API_KEY = "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30"
visitor_data = "CgtCM1BZUVZKYVZubyjvmd7LBjIKCgJJThIEGgAgFA%3D%3D"

def hit_web_remix_browse(browse_id):
    print(f"\n--- Hitting Browse (ID: {browse_id}) with WEB_REMIX ---")
    url = f"https://music.youtube.com/youtubei/v1/browse?key={API_KEY}"
    
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Safari/537.36",
        "Content-Type": "application/json",
        "X-YouTube-Client-Name": "67",
        "X-YouTube-Client-Version": "1.20230815.01.00",
        "X-Goog-Visitor-Id": visitor_data
    }
    
    payload = {
        "context": {
            "client": {
                "clientName": "WEB_REMIX",
                "clientVersion": "1.20230815.01.00",
                "gl": "IN",
                "hl": "en",
                "visitorData": visitor_data
            }
        },
        "browseId": browse_id
    }

    try:
        response = requests.post(url, headers=headers, json=payload, verify=False, timeout=10)
        print(f"Status: {response.status_code}")
        if response.status_code == 200:
            print("  !!! SUCCESS !!!")
            if 'musicSamplesShelfRenderer' in response.text:
                print("  !!! FOUND musicSamplesShelfRenderer !!!")
            else:
                try:
                    data = response.json()
                    print(f"  Top keys: {list(data.keys())}")
                    # If it redirects or shows "Open in App", look for those strings
                    if 'Open the app' in response.text or 'mealbar' in response.text:
                        print("  Response contains 'Open the app' / mealbar prompts.")
                except:
                    print("  Parsed 200, not JSON.")
        else:
            print(f"  Failed: {response.text[:200]}")
    except Exception as e:
        print(f"Error: {e}")

hit_web_remix_browse("FEmusic_samples")
hit_web_remix_browse("FEmusic_home")
