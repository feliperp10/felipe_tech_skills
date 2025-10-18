import requests
import json
import urllib3
import os
import pandas as pd

VT_API_KEY = os.environ.get('VT_API_KEY')

if not VT_API_KEY: 
    raise TypeError("Error: Invalid or missing API key")

#Getting IP address report:
ip = str (input("Type any IPv4 or IPv6 address: "))
get_ip_report_url = "https://www.virustotal.com/api/v3/ip_addresses/" + ip

headers = {
    "accept": "application/json",
    "x-apikey": VT_API_KEY
}
response = requests.get(get_ip_report_url, headers=headers)

#Checking if the request was well successfull

if response.status_code != 200:
    print(f"Request error: Status {response.status_code}")
    print (response.text)
    exit()

#Data Extraction and Structuring:

data = response.json()
attributes = data.get('data', {}).get('attributes', {})

report_data = {
    "IP Address": data.get('data', {}).get('id', ip),
    "Country": attributes.get('country', 'N/A'),
    "ASN": f"AS{attributes.get('asn', 'N/A')}",
    "AS Owner": attributes.get('as_owner', 'N/A'),
    "VT Reputation": attributes.get('reputation', 'N/A'),
    "Malicious Engines": attributes.get('last_analysis_stats', {}).get('malicious', 0),
    "Harmless Engines": attributes.get('last_analysis_stats', {}).get('harmless', 0),
    "Undetected Engines": attributes.get('last_analysis_stats', {}).get('undetected', 0),
}

#Formatted Output without Pandas:
#Find the maximum length of the keys (Metric names) for perfect alignment:

max_key_length = max(len(key) for key in report_data.keys())

#Define the format string to align keys and values

format_line = "{:<" + str(max_key_length) + "} : {}"

print("\n" + "="*40)
print(f"VIRUSTOTAL IP ANALYSIS FOR: {ip}")
print("="*40)

#Print the header line, ensuring it also follows the alignment pattern
print(f"{'Metric':<{max_key_length}} : {'Value':>10}")
print("-"*(max_key_length + 13))

#Print the data rows
for metric, value in report_data.items():
    print(format_line.format(metric, value))
    
print("="*40)