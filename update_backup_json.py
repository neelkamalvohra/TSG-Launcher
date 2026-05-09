import json

# Read new JS from update_roster.py
with open(r'D:\Neel\ElectronProject\TSG_Application\update_roster.py', encoding='utf-8') as f:
    src = f.read()

marker = 'NEW_JS = r"""'
start = src.index(marker) + len(marker)
end = src.index('"""', start)
new_js = src[start:end].strip()

print(f"New JS: {new_js.split(chr(10))[0]}")
print(f"Length: {len(new_js)}, v3={('v3' in new_js)}, overflow={('overflow-x:hidden' in new_js)}")

# Read backup JSON
backup_path = r'D:\Neel\ElectronProject\TSG_Application\Backup_n8n\Roster_Web_Service.json'
with open(backup_path, encoding='utf-8') as f:
    data = json.load(f)

nodes = data['nodes']
updated = False
for node in nodes:
    if node.get('name') == 'HTML Builder':
        node['parameters']['jsCode'] = new_js
        updated = True
        print("Updated HTML Builder node.")
        break

if not updated:
    print("ERROR: HTML Builder node not found!")
    exit(1)

with open(backup_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)

print("Backup JSON saved successfully.")
